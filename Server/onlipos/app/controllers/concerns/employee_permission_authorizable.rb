# 従業員（Employee）の特定・PIN認証（承認）・権限チェックを各コントローラに提供する Concern
#
# 操作APIは「employee_id を送る」だけでは実行できない。PIN認証（verify_employee 等）で発行された
# 承認トークンを X-Operator-Approval ヘッダーで提示し、その担当者本人が操作していることを確認する。
module EmployeePermissionAuthorizable
  extend ActiveSupport::Concern

  STORE_EMPLOYEE_NOT_FOUND = "担当者が見つからないか、店舗の権限がありません".freeze
  APPROVAL_HEADER = "X-Operator-Approval".freeze
  MAX_APPROVALS = 50

  # 承認トークンに未対応の旧バージョンの端末を一時的に許可する（移行期間用。既定は拒否）
  def self.legacy_operator_auth_allowed?
    ActiveModel::Type::Boolean.new.cast(ENV["ALLOW_LEGACY_OPERATOR_AUTH"]) || false
  end

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

  # 従業員が permission_key を持ち、かつPIN認証済み（承認あり）でなければ 403 を返す。
  # 呼び出し側は `return if performed?` で後続処理を止めること。
  def authorize_employee!(employee, permission_key)
    require_permission!(employee, permission_key)
    return if performed?

    render_approval_required(permission_key) unless operator_approved?(employee, permission_key)
  end

  # 権限の有無だけを確認する（PIN認証そのものの処理で使う）
  def require_permission!(employee, permission_key)
    return if employee.permitted?(permission_key)

    label = Employee::PERMISSION_CATALOG[permission_key.to_s]
    render json: {
      success: false,
      message: "この操作の権限がありません（#{label}）",
      required_permission: permission_key.to_s
    }, status: :forbidden
  end

  # 担当者を特定しない参照系（理論在高など）で、いずれかの権限の承認があるかを確認する
  def require_any_approval!(*permission_keys)
    return if EmployeePermissionAuthorizable.legacy_operator_auth_allowed?
    return if permission_keys.any? { |key| approved_employee_for(key) }

    render_approval_required(permission_keys.first)
  end

  # 二重承認（返品・取消）。異なる2名以上がそれぞれPIN認証済みで権限を持つことを確認し、担当者の配列を返す。
  # 満たさない場合は 403 を描画して nil を返す。
  def require_dual_approval!(employee_ids, permission_key, action_label:)
    ids = Array(employee_ids).map(&:to_i).uniq
    if ids.size < 2
      render json: { success: false, message: "#{action_label}には2名以上の従業員認証が必要です" }, status: :forbidden
      return
    end

    employees = ids.filter_map { |id| find_store_employee(id) }
    if employees.size < 2 || employees.size < ids.size
      render json: { success: false, message: "認証された従業員が不足しているか、店舗権限がありません" }, status: :forbidden
      return
    end

    without_permission = employees.reject { |e| e.permitted?(permission_key) }
    if without_permission.any?
      render json: { success: false, message: "#{action_label}権限がありません: #{without_permission.map(&:name).join('、')}" }, status: :forbidden
      return
    end

    unless employees.all? { |e| operator_approved?(e, permission_key) }
      render_approval_required(permission_key)
      return
    end

    employees
  end

  # 提示された有効な承認（この端末で発行されたもののみ）
  def presented_approvals
    @presented_approvals ||= begin
      tokens = request.headers[APPROVAL_HEADER].to_s.split(",").map(&:strip).reject(&:blank?).first(MAX_APPROVALS)
      digests = tokens.map { |t| OperatorApproval.digest(t) }
      OperatorApproval.active.includes(:employee).where(pos_token_id: @current_pos.id, token_digest: digests).to_a
    end
  end

  def operator_approved?(employee, permission_key)
    return true if EmployeePermissionAuthorizable.legacy_operator_auth_allowed?

    presented_approvals.any? { |a| a.employee_id == employee.id && a.covers?(permission_key) }
  end

  # 指定権限の承認を持ち、今も権限・店舗アクセスがある担当者（値引き承認など、操作者と承認者が別の場合に使う）
  def approved_employee_for(permission_key)
    presented_approvals.map { |a| a.employee if a.covers?(permission_key) }.compact.find do |employee|
      employee.permitted?(permission_key) && employee.can_access_store?(@current_pos.store)
    end
  end

  # 一度きりの承認を消費する。すでに使われていれば false
  def consume_approvals(employees, permission_key, purpose)
    return true if EmployeePermissionAuthorizable.legacy_operator_auth_allowed?

    employees.all? do |employee|
      approval = presented_approvals.find { |a| a.employee_id == employee.id && a.covers?(permission_key) }
      approval&.consume!(purpose)
    end
  end

  def render_approval_required(permission_key)
    render json: {
      success: false,
      code: "operator_approval_required",
      message: "担当者のPIN認証が必要です。認証の有効期限が切れた場合は、もう一度認証してください",
      required_permission: permission_key.to_s
    }, status: :forbidden
  end
end
