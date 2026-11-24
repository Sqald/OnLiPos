# 契約アカウントの設定（インボイス登録番号・消費税の端数処理など）
class Dashboard::AccountSettingsController < Dashboard::BaseController
  requires_role read: "manager", write: "owner"

  def show
    @account = current_account
  end

  def update
    @account = current_account
    if @account.update(account_params)
      redirect_to dashboard_account_settings_path, notice: "設定を保存しました。端末には次回の同期で反映されます。", status: :see_other
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def account_params
    params.require(:user).permit(:invoice_registration_number, :tax_rounding_method, :point_yen_per_point, :receipt_footer, :digital_receipt_enabled)
  end
end
