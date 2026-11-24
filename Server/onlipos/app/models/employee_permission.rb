# Employee に付与された個別権限（Employee::PERMISSION_CATALOG のキーを1件保持する）
class EmployeePermission < ApplicationRecord
  include Auditable

  def audit_name = "#{employee&.name}: #{Employee::PERMISSION_CATALOG[permission]}"
  belongs_to :employee
  validates :permission, presence: true
end
