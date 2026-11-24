# セキュリティ設定の変更前に、パスワードを再入力してもらう画面
class Dashboard::ReauthenticationsController < Dashboard::BaseController
  requires_role read: "viewer", write: "viewer"

  def new
  end

  def create
    # 失敗は Devise の凍結判定（lockable）に加算する
    unless current_user.valid_for_authentication? { current_user.valid_password?(params[:password].to_s) }
      if current_user.respond_to?(:access_locked?) && current_user.access_locked?
        sign_out(:user)
        return redirect_to new_user_session_path, alert: I18n.t("devise.failure.locked"), status: :see_other
      end
      flash.now[:alert] = "パスワードが正しくありません。"
      return render :new, status: :unprocessable_entity
    end

    current_user.reset_failed_attempts! if current_user.respond_to?(:reset_failed_attempts!)
    session[:reauthenticated_at] = Time.current.to_i
    redirect_to session.delete(:reauth_return_to) || dashboard_security_path, notice: "確認しました。操作を続けてください。", status: :see_other
  end
end
