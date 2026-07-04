class EmployeePermission < ApplicationRecord
  belongs_to :employee
  validates :permission, presence: true
end
