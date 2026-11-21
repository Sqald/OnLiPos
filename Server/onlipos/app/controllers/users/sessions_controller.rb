# frozen_string_literal: true

# ダッシュボードへのログイン（1段階目: メールアドレス＋パスワード）。
# パスワードが正しくてもここではログインさせず、2段階目（Users::MfaController）へ進める。
# 失敗回数・凍結・メール未確認の扱いは Devise の標準（lockable / confirmable）に従う。
class Users::SessionsController < Devise::SessionsController
  # POST /users/sign_in
  def create
    email = params.dig(:user, :email).to_s.strip
    password = params.dig(:user, :password).to_s
    user = User.find_for_authentication(email: email)

    unless user && user.valid_for_authentication? { user.valid_password?(password) }
      # 存在しないメールアドレスでも処理時間を揃える（アカウントの有無を推測されにくくする）
      User.new.password = password unless user
      return render_login_failure(email, user&.respond_to?(:access_locked?) && user.access_locked? ? :locked : :invalid)
    end

    unless user.active_for_authentication?
      return render_login_failure(email, user.inactive_message)
    end

    start_mfa_pending(user, remember: params.dig(:user, :remember_me) == "1")
    redirect_to user_mfa_path
  end

  private

  def render_login_failure(email, reason)
    self.resource = User.new(email: email)
    flash.now[:alert] = I18n.t("devise.failure.#{reason}", authentication_keys: "メールアドレス",
                               default: I18n.t("devise.failure.invalid", authentication_keys: "メールアドレス"))
    render :new, status: :unprocessable_entity
  end
end
