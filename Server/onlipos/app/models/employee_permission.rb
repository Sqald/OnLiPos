# Employee に付与された個別権限（Employee::PERMISSION_CATALOG のキーを1件保持する）
class EmployeePermission < ApplicationRecord
  belongs_to :employee
  validates :permission, presence: true
end
