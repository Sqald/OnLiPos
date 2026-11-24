# 従業員コード＋PINの検証（ロック・店舗権限の確認を含む）。
# 成功すれば従業員を返し、失敗時はエラーを描画して nil を返す。
module EmployeePinAuthenticatable
  private

  def authenticated_employee(not_found_message: "従業員コードまたはPINが正しくありません")
    employee = @current_pos.store.user.employees.find_by(code: params[:code].to_s)
    pin = params[:pin].to_s

    # 従業員が存在しない、またはPINが空の場合は即座に失敗させる
    return pin_error(not_found_message, :unauthorized) if employee.nil? || pin.blank?

    if employee.access_locked?
      return pin_error(I18n.t("api.v1.pos_devices.top_user_login.locked", default: "アカウントがロックされています"), :forbidden)
    end

    unless employee.authenticate_pin(pin)
      employee.increment_failed_attempts
      return pin_error(I18n.t("api.v1.pos_devices.top_user_login.failure", default: "PINが正しくありません"), :unauthorized)
    end

    employee.unlock_access!
    unless employee.can_access_store?(@current_pos.store)
      return pin_error(I18n.t("api.v1.pos_devices.top_user_login.not_authorized_for_store", default: "店舗権限がありません"), :forbidden)
    end

    employee
  end

  def pin_error(message, status)
    render json: { success: false, message: message }, status: status
    nil
  end
end
