# 従業員（Employee）の権限チェックを各コントローラに提供する Concern
module EmployeePermissionAuthorizable
  extend ActiveSupport::Concern

  private

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
