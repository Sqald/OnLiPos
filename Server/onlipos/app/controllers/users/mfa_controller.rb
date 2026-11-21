# ダッシュボードログインの2段階目（MFA）。パスワード確認済み（session[:mfa_pending]）のユーザーのみが使える。
# - MFA 設定済み: 認証アプリのコード / パスキー / リカバリーコードのいずれかで確認してログイン
# - MFA 未設定  : 認証アプリかパスキーのどちらかを登録してからログイン（登録時にリカバリーコードを発行）
class Users::MfaController < ApplicationController
  include WebauthnRelyingParty

  before_action :require_pending_user

  # GET /users/mfa
  def show
    @user = mfa_pending_user
    if @user.mfa_enabled?
      render :challenge
    else
      session[:mfa_setup_secret] ||= User.generate_otp_secret
      @otp_secret = session[:mfa_setup_secret]
      @otp_uri = @user.otp_provisioning_uri(@otp_secret)
      render :setup
    end
  end

  # POST /users/mfa/totp — 認証アプリのコード確認（未設定なら登録も兼ねる）
  def verify_totp
    user = mfa_pending_user
    code = params[:code].to_s

    if user.mfa_enabled?
      return complete_and_redirect(user) if user.verify_otp(code)
    elsif (secret = session[:mfa_setup_secret]) && (timestep = MultiFactorAuthenticatable.verify_totp(secret, code))
      user.enable_otp!(secret, timestep)
      return complete_setup_and_redirect(user)
    end

    fail_and_redirect(user, "確認コードが正しくありません。認証アプリに表示されている6桁のコードを入力してください。")
  end

  # POST /users/mfa/recovery — リカバリーコードでのログイン（端末紛失時）
  def verify_recovery
    user = mfa_pending_user
    if user.mfa_enabled? && user.consume_recovery_code!(params[:recovery_code])
      complete_mfa_sign_in(user)
      notice = "リカバリーコードでログインしました（残り#{user.recovery_codes_remaining}個）。"
      notice += " 2段階認証の設定を見直してください。" if user.recovery_codes_remaining <= 3
      return redirect_to dashboard_security_path, notice: notice
    end
    fail_and_redirect(user, "リカバリーコードが正しくないか、使用済みです。")
  end

  # POST /users/mfa/passkey/options — パスキー認証（設定済み）または登録（未設定）用のチャレンジを発行
  def passkey_options
    user = mfa_pending_user
    options =
      if user.mfa_enabled?
        webauthn_relying_party.options_for_authentication(
          allow: user.passkeys.pluck(:external_id), user_verification: "required"
        )
      else
        webauthn_relying_party.options_for_registration(
          user: { id: user.ensure_webauthn_id!, name: user.email, display_name: user.login_name },
          authenticator_selection: { resident_key: "preferred", user_verification: "required" }
        )
      end
    session[:webauthn_challenge] = options.challenge
    render json: options
  end

  # POST /users/mfa/passkey — パスキーの応答を検証してログイン（未設定ならパスキーを登録してログイン）
  def verify_passkey
    user = mfa_pending_user
    challenge = session.delete(:webauthn_challenge)
    payload = webauthn_payload
    return render_passkey_error(user, "認証の有効期限が切れました。もう一度お試しください。") if challenge.blank?

    if user.mfa_enabled?
      credential = WebAuthn::Credential.from_get(payload["credential"], relying_party: webauthn_relying_party)
      passkey = user.passkeys.find_by(external_id: credential.id)
      return render_passkey_error(user, "このパスキーは登録されていません。") unless passkey

      credential.verify(challenge, public_key: passkey.public_key, sign_count: passkey.sign_count, user_verification: true)
      passkey.update!(sign_count: credential.sign_count, last_used_at: Time.current)
      complete_mfa_sign_in(user)
      render json: { redirect: after_sign_in_path_for(user) }
    else
      credential = webauthn_relying_party.verify_registration(payload["credential"], challenge, user_verification: true)
      user.passkeys.create!(
        external_id: credential.id, public_key: credential.public_key, sign_count: credential.sign_count,
        nickname: payload["nickname"].to_s.strip.presence&.slice(0, 50) || "パスキー", last_used_at: Time.current
      )
      codes = user.regenerate_recovery_codes!
      complete_mfa_sign_in(user)
      session[:mfa_new_recovery_codes] = codes
      render json: { redirect: dashboard_security_recovery_codes_path }
    end
  rescue WebAuthn::Error, ArgumentError, KeyError, NoMethodError => e
    Rails.logger.info "Passkey verification failed: #{e.class}: #{e.message}"
    render_passkey_error(user, "パスキーを確認できませんでした。もう一度お試しください。")
  end

  # DELETE /users/mfa — 2段階目を中止してログイン画面へ戻る
  def cancel
    clear_mfa_pending
    redirect_to new_user_session_path, status: :see_other
  end

  private

  def require_pending_user
    return if mfa_pending_user

    clear_mfa_pending
    respond_to do |format|
      format.json { render json: { error: "ログインの有効期限が切れました。もう一度ログインしてください。", redirect: new_user_session_path }, status: :unauthorized }
      format.any { redirect_to new_user_session_path, alert: "ログインの有効期限が切れました。もう一度ログインしてください。" }
    end
  end

  def complete_and_redirect(user)
    complete_mfa_sign_in(user)
    redirect_to after_sign_in_path_for(user), notice: I18n.t("devise.sessions.signed_in")
  end

  # 初回登録の完了: ログインさせ、リカバリーコードを一度だけ表示する画面へ
  def complete_setup_and_redirect(user)
    codes = user.regenerate_recovery_codes!
    complete_mfa_sign_in(user)
    session[:mfa_new_recovery_codes] = codes
    redirect_to dashboard_security_recovery_codes_path
  end

  def fail_and_redirect(user, message)
    if record_mfa_failure(user)
      redirect_to new_user_session_path, alert: "確認に失敗した回数が多すぎます。もう一度パスワードからログインしてください。"
    else
      redirect_to user_mfa_path, alert: message
    end
  end

  def render_passkey_error(user, message)
    if record_mfa_failure(user)
      render json: { error: "確認に失敗した回数が多すぎます。もう一度パスワードからログインしてください。", redirect: new_user_session_path }, status: :unauthorized
    else
      render json: { error: message }, status: :unprocessable_entity
    end
  end
end
