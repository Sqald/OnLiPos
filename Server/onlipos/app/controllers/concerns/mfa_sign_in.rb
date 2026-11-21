# ダッシュボードログインの多要素認証（MFA）を必須にするための共通処理。ApplicationController に include する。
#
# ログインは2段階:
#   1. メールアドレス＋パスワード（Users::SessionsController#create）が正しければ「MFA待ち」状態にするだけで、
#      まだログインさせない（session[:mfa_pending]）
#   2. 認証アプリのコード / パスキー / リカバリーコードのいずれかを確認できたらログインさせる（Users::MfaController）
#      MFA 未設定のユーザーは、この段階でどちらかを登録してからログインする
# ログイン完了時にだけ warden のセッションへ印（mfa: true）を付け、印のないログイン状態は無効にする
# （MFA 導入前のセッションや、パスワード再設定などの別経路でログインした状態を締め出すため）。
module MfaSignIn
  extend ActiveSupport::Concern

  PENDING_TTL = 10.minutes
  MAX_PENDING_FAILURES = 5
  SESSION_MARK = "mfa".freeze

  included do
    before_action :enforce_mfa_session
    helper_method :mfa_pending_user
  end

  private

  # MFA を通らずにログイン状態になっている場合は、ログアウトさせてログインからやり直させる
  # ※ user_signed_in? は認証ストラテジ（パスワード等）を実行してしまうため使わず、セッション上のログイン状態だけを見る
  def enforce_mfa_session
    return unless warden.user(:user)
    return if warden.session(:user)[SESSION_MARK]

    sign_out(:user)
    redirect_to new_user_session_path, alert: "セキュリティ強化のため、2段階認証でのログインが必要です。もう一度ログインしてください。"
  end

  def start_mfa_pending(user, remember:)
    reset_session_keeping_nothing
    session[:mfa_pending] = { "user_id" => user.id, "at" => Time.current.to_i, "remember" => remember, "failures" => 0 }
  end

  # パスワード確認済みで MFA 待ちのユーザー（期限切れなら nil）
  def mfa_pending_user
    return @mfa_pending_user if defined?(@mfa_pending_user)
    pending = session[:mfa_pending]
    @mfa_pending_user =
      if pending.is_a?(Hash) && pending["at"].to_i > PENDING_TTL.ago.to_i
        User.find_by(id: pending["user_id"])
      end
  end

  def clear_mfa_pending
    session.delete(:mfa_pending)
    session.delete(:mfa_setup_secret)
    session.delete(:webauthn_challenge)
    @mfa_pending_user = nil
  end

  # 2段階目の失敗を記録する。アカウントの失敗回数（凍結判定）にも加算し、
  # この画面での失敗が上限に達したらパスワード入力からやり直させる。戻り値: やり直しが必要なら true
  def record_mfa_failure(user)
    user.valid_for_authentication? { false }
    pending = session[:mfa_pending]
    pending["failures"] = pending["failures"].to_i + 1
    session[:mfa_pending] = pending
    if pending["failures"] >= MAX_PENDING_FAILURES || (user.respond_to?(:access_locked?) && user.access_locked?)
      clear_mfa_pending
      true
    else
      false
    end
  end

  # 2段階目まで確認できたユーザーをログインさせる
  def complete_mfa_sign_in(user)
    remember = session.dig(:mfa_pending, "remember")
    clear_mfa_pending
    # 「ログインしたままにする」は Devise の rememberable フックが sign_in 時に Cookie を発行する
    user.remember_me = true if remember && user.respond_to?(:remember_me=)
    sign_in(:user, user)
    warden.session(:user)[SESSION_MARK] = true
  end

  # セッション固定化対策: 認証状態が変わる前にセッションIDを振り直す
  def reset_session_keeping_nothing
    return_to = session["user_return_to"]
    reset_session
    session["user_return_to"] = return_to if return_to
  end
end
