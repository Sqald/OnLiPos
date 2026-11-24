# ダッシュボードのセキュリティ設定（2段階認証）。
# 認証アプリ・パスキーの追加と削除、リカバリーコードの再発行を行う。
# ログインには2段階目の要素が最低1つ必要なため、最後の1つは削除できない。
class Dashboard::SecurityController < Dashboard::BaseController
  include WebauthnRelyingParty

  # 自分自身の設定なので、閲覧のみのメンバーも変更できる。変更には直近のパスワード再入力が必要
  requires_role read: "viewer", write: "viewer"
  before_action :require_recent_authentication, except: [ :show, :recovery_codes ]

  # GET /dashboard/security
  def show
    @passkeys = current_user.passkeys.order(:created_at)
  end

  # GET /dashboard/security/totp/new — 認証アプリの登録（QRコード表示）
  def new_totp
    if current_user.otp_enabled?
      return redirect_to dashboard_security_path, alert: "認証アプリはすでに登録されています。変更する場合は一度解除してください。"
    end
    session[:mfa_setup_secret] ||= User.generate_otp_secret
    @otp_secret = session[:mfa_setup_secret]
    @otp_uri = current_user.otp_provisioning_uri(@otp_secret)
  end

  # POST /dashboard/security/totp
  def create_totp
    secret = session[:mfa_setup_secret]
    timestep = secret && MultiFactorAuthenticatable.verify_totp(secret, params[:code])
    unless timestep
      return redirect_to dashboard_new_security_totp_path, alert: "確認コードが正しくありません。認証アプリに表示されている6桁のコードを入力してください。"
    end

    current_user.enable_otp!(secret, timestep)
    session.delete(:mfa_setup_secret)
    SecurityNotifier.notify(current_user, "認証アプリを登録しました")
    redirect_to dashboard_security_path, notice: "認証アプリを登録しました。"
  end

  # DELETE /dashboard/security/totp
  def destroy_totp
    unless current_user.passkeys.exists?
      return redirect_to dashboard_security_path, alert: "2段階認証の方法が無くなるため解除できません。先にパスキーを登録してください。", status: :see_other
    end
    current_user.disable_otp!
    SecurityNotifier.notify(current_user, "認証アプリの登録を解除しました")
    redirect_to dashboard_security_path, notice: "認証アプリの登録を解除しました。", status: :see_other
  end

  # POST /dashboard/security/passkeys/options — パスキー登録用のチャレンジを発行
  def passkey_options
    options = webauthn_relying_party.options_for_registration(
      user: { id: current_user.ensure_webauthn_id!, name: current_user.email, display_name: current_user.login_name },
      exclude: current_user.passkeys.pluck(:external_id),
      authenticator_selection: { resident_key: "preferred", user_verification: "required" }
    )
    session[:webauthn_challenge] = options.challenge
    render json: options
  end

  # POST /dashboard/security/passkeys — パスキーの登録
  def create_passkey
    challenge = session.delete(:webauthn_challenge)
    return render json: { error: "登録の有効期限が切れました。もう一度お試しください。" }, status: :unprocessable_entity if challenge.blank?

    payload = webauthn_payload
    credential = webauthn_relying_party.verify_registration(payload["credential"], challenge, user_verification: true)
    current_user.passkeys.create!(
      external_id: credential.id, public_key: credential.public_key, sign_count: credential.sign_count,
      nickname: payload["nickname"].to_s.strip.presence&.slice(0, 50) || "パスキー"
    )
    SecurityNotifier.notify(current_user, "パスキーを登録しました")
    flash[:notice] = "パスキーを登録しました。"
    render json: { redirect: dashboard_security_path }
  rescue WebAuthn::Error, ActiveRecord::RecordInvalid, ArgumentError, KeyError, NoMethodError => e
    Rails.logger.info "Passkey registration failed: #{e.class}: #{e.message}"
    render json: { error: "パスキーを登録できませんでした。もう一度お試しください。" }, status: :unprocessable_entity
  end

  # DELETE /dashboard/security/passkeys/:id
  def destroy_passkey
    passkey = current_user.passkeys.find(params[:id])
    if !current_user.otp_enabled? && current_user.passkeys.count <= 1
      return redirect_to dashboard_security_path, alert: "2段階認証の方法が無くなるため削除できません。先に別のパスキーか認証アプリを登録してください。", status: :see_other
    end
    passkey.destroy!
    SecurityNotifier.notify(current_user, "パスキー「#{passkey.nickname}」を削除しました")
    redirect_to dashboard_security_path, notice: "パスキー「#{passkey.nickname}」を削除しました。", status: :see_other
  end

  # POST /dashboard/security/sign_out_everywhere — この端末を含む、すべてのログインを無効にする
  def sign_out_everywhere
    current_user.revoke_sessions!
    SecurityNotifier.notify(current_user, "すべての端末からログアウトしました")
    sign_out(:user)
    redirect_to new_user_session_path, notice: "すべての端末からログアウトしました。", status: :see_other
  end

  # POST /dashboard/security/recovery_codes — リカバリーコードを作り直す（以前のコードは無効）
  def regenerate_recovery_codes
    session[:mfa_new_recovery_codes] = current_user.regenerate_recovery_codes!
    SecurityNotifier.notify(current_user, "リカバリーコードを再発行しました")
    redirect_to dashboard_security_recovery_codes_path
  end

  # GET /dashboard/security/recovery_codes — 発行直後のリカバリーコードを一度だけ表示する
  def recovery_codes
    @codes = session.delete(:mfa_new_recovery_codes)
    redirect_to dashboard_security_path if @codes.blank?
  end
end
