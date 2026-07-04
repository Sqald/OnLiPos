require "test_helper"

class EmployeeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @employee = @user.employees.create!(code: "EP001", name: "テスト従業員")
  end

  test "permitted? returns false when no permissions exist" do
    assert_not @employee.permitted?("refund")
  end

  test "permitted? returns true when permission exists" do
    @employee.employee_permissions.create!(permission: "refund")
    assert @employee.permitted?("refund")
  end

  test "permitted? accepts symbol key" do
    @employee.employee_permissions.create!(permission: "open_register")
    assert @employee.permitted?(:open_register)
  end

  test "permission_keys returns empty array when no permissions" do
    assert_equal [], @employee.permission_keys
  end

  test "permission_keys returns all granted permissions" do
    @employee.employee_permissions.create!(permission: "refund")
    @employee.employee_permissions.create!(permission: "open_register")
    keys = @employee.permission_keys
    assert_includes keys, "refund"
    assert_includes keys, "open_register"
    assert_equal 2, keys.size
  end

  test "sync_permissions adds new and removes revoked" do
    @employee.employee_permissions.create!(permission: "refund")
    @employee.employee_permissions.create!(permission: "open_register")

    @employee.sync_permissions(%w[refund cash_check])

    assert @employee.permitted?("refund"),        "refund は維持されるべき"
    assert @employee.permitted?("cash_check"),     "cash_check は追加されるべき"
    assert_not @employee.permitted?("open_register"), "open_register は削除されるべき"
  end

  test "sync_permissions ignores keys not in PERMISSION_CATALOG" do
    @employee.sync_permissions(%w[refund unknown_key hack])
    assert @employee.permitted?("refund")
    assert_not @employee.permitted?("unknown_key")
    assert_not @employee.permitted?("hack")
  end

  test "sync_permissions with empty array removes all permissions" do
    @employee.employee_permissions.create!(permission: "refund")
    @employee.sync_permissions([])
    assert_not @employee.permitted?("refund")
    assert_equal [], @employee.permission_keys
  end

  test "PERMISSION_CATALOG contains expected keys" do
    expected = %w[open_register close_register cash_check cash_pickup refund view_sales edit_prices view_journal inventory discount]
    expected.each do |key|
      assert_includes Employee::PERMISSION_CATALOG.keys, key
    end
  end
end
