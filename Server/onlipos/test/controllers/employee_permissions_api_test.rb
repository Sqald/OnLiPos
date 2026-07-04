require "test_helper"

# 従業員権限の API 強制テスト
# - open / cash_check / close_register は開設者の権限では制御しない（開設者≠利用者）
# - refund のみ操作者本人の権限を確認する
class EmployeePermissionsApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "permtest",
      email: "permtest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "権限",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "権限テスト店", ascii_name: "permteststore")
    @pos = @store.pos_tokens.create!(
      name: "POS1", ascii_name: "pos1",
      password: "PosPass1!", password_confirmation: "PosPass1!"
    )
    @pos.update_columns(token: SecureRandom.hex(32))

    @employee = @user.employees.create!(code: "P001", name: "権限なし従業員", pin: "1234")
    @employee.stores << @store

    @full_employee = @user.employees.create!(code: "P002", name: "全権限従業員", pin: "5678")
    @full_employee.stores << @store
    Employee::PERMISSION_CATALOG.each_key do |k|
      @full_employee.employee_permissions.create!(permission: k)
    end
  end

  # ── top_user_login に permissions を含む ───────────────────────

  test "top_user_login レスポンスに permissions が含まれる" do
    @full_employee.update_columns(pin_digest: BCrypt::Password.create("5678"))

    post "/api/v1/pos_devices/top_user_login",
         params: { code: @full_employee.code, pin: "5678" },
         headers: { "Authorization" => "Bearer #{@pos.token}" },
         as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    assert data["success"]
    assert_kind_of Array, data["permissions"]
    assert_includes data["permissions"], "refund"
  end

  # ── verify_employee に permissions を含む ─────────────────────

  test "verify_employee レスポンスに permissions が含まれる" do
    @full_employee.update_columns(pin_digest: BCrypt::Password.create("5678"))

    post "/api/v1/pos_devices/verify_employee",
         params: { code: @full_employee.code, pin: "5678" },
         headers: { "Authorization" => "Bearer #{@pos.token}" },
         as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    assert data["success"]
    assert_kind_of Array, data["permissions"]
  end

  # ── check_operator に permissions を含む ─────────────────────

  test "check_operator レスポンスに permissions が含まれる" do
    @employee.employee_permissions.create!(permission: "refund")

    post "/api/v1/pos_devices/check_operator",
         params: { code: @employee.code },
         headers: { "Authorization" => "Bearer #{@pos.token}" },
         as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    assert data["success"]
    assert_equal [ "refund" ], data["permissions"]
  end

  # ── refund 権限チェック ────────────────────────────────────────

  test "refund 権限なしの従業員が含まれると返品が 403 になる" do
    # @employee は refund 権限なし
    # @full_employee は全権限あり
    sale = Sale.create!(
      store: @store, user: @user, pos_token: @pos,
      receipt_number: "permtest-permteststore-1-00000001",
      total_amount: 1000, subtotal_ex_tax: 909, tax_amount: 91
    )

    post "/api/v1/refunds",
         params: {
           receipt_number: sale.receipt_number,
           employee_ids: [ @employee.id, @full_employee.id ],
           details: []
         },
         headers: { "Authorization" => "Bearer #{@pos.token}" },
         as: :json

    assert_response :forbidden
    data = JSON.parse(response.body)
    assert_equal false, data["success"]
    assert_includes data["message"], "返品権限がありません"
  end

  test "全員が refund 権限を持つ場合は返品処理が進む（明細不足で bad_request）" do
    @employee.employee_permissions.create!(permission: "refund")
    sale = Sale.create!(
      store: @store, user: @user, pos_token: @pos,
      receipt_number: "permtest-permteststore-1-00000002",
      total_amount: 1000, subtotal_ex_tax: 909, tax_amount: 91
    )

    post "/api/v1/refunds",
         params: {
           receipt_number: sale.receipt_number,
           employee_ids: [ @employee.id, @full_employee.id ],
           details: []
         },
         headers: { "Authorization" => "Bearer #{@pos.token}" },
         as: :json

    # 権限チェックは通過し、明細が空なので bad_request になる
    assert_response :bad_request
  end
end
