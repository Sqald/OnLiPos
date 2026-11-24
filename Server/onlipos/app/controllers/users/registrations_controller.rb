# frozen_string_literal: true

# ユーザー登録・アカウント編集・退会。許可パラメータは ApplicationController#configure_permitted_parameters で設定する。
class Users::RegistrationsController < Devise::RegistrationsController
  include DashboardAccess

  # マイページはダッシュボードと同じ枠（メニュー付き）で表示する
  layout -> { action_name.in?(%w[edit update]) && user_signed_in? ? "dashboard" : "application" }
  # DELETE /users — 退会。現在のパスワードを確認し、取引記録が残る契約は削除しない（法定保存のため）
  def destroy
    unless resource.valid_password?(params[:current_password].to_s)
      return redirect_to edit_user_registration_path, alert: "退会するには現在のパスワードを入力してください。", status: :see_other
    end

    if resource.destroy
      Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name)
      redirect_to root_path, notice: I18n.t("devise.registrations.destroyed"), status: :see_other
    else
      redirect_to edit_user_registration_path, status: :see_other,
                  alert: "売上などの取引記録は法令により保存が必要なため、画面からは退会できません。サービス管理者へご連絡ください。"
    end
  rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotDestroyed
    redirect_to edit_user_registration_path, status: :see_other,
                alert: "取引記録が残っているため退会できません。サービス管理者へご連絡ください。"
  end
end
