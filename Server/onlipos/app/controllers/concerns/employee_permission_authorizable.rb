# 従業員（Employee）の特定・権限チェックを各コントローラに提供する Concern
module EmployeePermissionAuthorizable
  extend ActiveSupport::Concern

  STORE_EMPLOYEE_NOT_FOUND = "担当者が見つからないか、店舗の権限がありません".freeze

  private

  # employee_id から、アクセス元POS端末の店舗を操作できる従業員を返す。
  # オーナー配下の従業員のみを対象にし、他社・他店舗の従業員IDは通さない（権限昇格防止）。
  # 該当しない場合は nil。
  def find_store_employee(employee_id)
    store = @current_pos.store
    employee = store.user.employees.find_by(id: employee_id)
    employee if employee&.can_access_store?(store)
  end

  # find_store_employee と同じだが、該当しない場合は 403 を描画して nil を返す。
  # 呼び出し側は `return unless employee` で後続処理を止めること。
  def require_store_employee!(employee_id, message: STORE_EMPLOYEE_NOT_FOUND)
    employee = find_store_employee(employee_id)
    render json: { success: false, message: message }, status: :forbidden unless employee
    employee
  end

  # 従業員が permission_key を持たない場合は 403 を返す。
  # 呼び出し側は `return if performed?` で後続処理を止めること。
  def authorize_employee!(employee, permission_key)
    return if employee.permitted?(permission_key)

    label = Employee::PERMISSION_CATALOG[permission_key.to_s]
    render json: {
      success: false,
      message: "この操作の権限がありません（#{label}）",
      required_permission: permission_key.to_s
    }, status: :forbidden
  end
end
