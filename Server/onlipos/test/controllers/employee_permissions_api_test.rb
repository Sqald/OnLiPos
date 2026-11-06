require "test_helper"

# 従業員権限の API 強制テスト
# - 各操作（開設・レジ金チェック・精算・在庫入出荷・売上閲覧・返品）は操作を行う担当者本人の権限を確認する
# - top_user_login / verify_employee は permission 指定時、ログイン（担当者認証）の時点で権限を確認する
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

  # ── ログイン時（担当者認証時）の権限チェック ──────────────────

  def verify(employee, pin, permission)
    employee.update_columns(pin_digest: BCrypt::Password.create(pin))
    post "/api/v1/pos_devices/verify_employee",
         params: { code: employee.code, pin: pin, permission: permission },
         headers: auth_headers,
         as: :json
  end

  def auth_headers
    { "Authorization" => "Bearer #{@pos.token}" }
  end

  test "verify_employee は permission 指定時に権限がなければ 403" do
    verify(@employee, "1234", "close_register")

    assert_response :forbidden
    data = JSON.parse(response.body)
    assert_equal "close_register", data["required_permission"]
  end

  test "verify_employee は permission 指定時に権限があれば成功" do
    verify(@full_employee, "5678", "close_register")

    assert_response :ok
    assert JSON.parse(response.body)["success"]
  end

  test "verify_employee に不明な permission を指定すると 400" do
    verify(@full_employee, "5678", "no_such_permission")
    assert_response :bad_request
  end

  test "top_user_login は permission 指定時に権限がなければ 403" do
    @employee.update_columns(pin_digest: BCrypt::Password.create("1234"))
    post "/api/v1/pos_devices/top_user_login",
         params: { code: @employee.code, pin: "1234", permission: "open_register" },
         headers: auth_headers,
         as: :json

    assert_response :forbidden
  end

  # ── 各操作エンドポイントでの権限チェック ─────────────────────

  def drawer
    { "10000" => 1, "5000" => 0, "1000" => 0, "500" => 0, "100" => 0, "50" => 0, "10" => 0, "5" => 0, "1" => 0 }
  end

  test "open_register 権限がなければレジ開設は 403" do
    post "/api/v1/pos_devices/open",
         params: { employee_id: @employee.id, open_date: Date.current.to_s, cash_drawer: drawer },
         headers: auth_headers, as: :json

    assert_response :forbidden
    assert_equal 0, @pos.register_sessions.count
  end

  test "cash_check 権限がなければレジ金チェックは 403" do
    post "/api/v1/pos_devices/cash_check",
         params: { employee_id: @employee.id, cash_drawer: drawer },
         headers: auth_headers, as: :json

    assert_response :forbidden
    assert_equal 0, CashLog.count
  end

  test "close_register 権限がなければレジ精算は 403、権限があれば成功" do
    post "/api/v1/pos_devices/close_register",
         params: { employee_id: @employee.id, cash_drawer: drawer },
         headers: auth_headers, as: :json
    assert_response :forbidden

    post "/api/v1/pos_devices/close_register",
         params: { employee_id: @full_employee.id, cash_drawer: drawer },
         headers: auth_headers, as: :json
    assert_response :ok
  end

  test "inventory 権限がなければ在庫入出荷は 403" do
    product = @user.products.create!(code: "4900000000009", name: "在庫商品", price: 100, tax_rate: 10)
    post "/api/v1/store_stocks/move",
         params: { employee_id: @employee.id, movements: [ { jan_code: product.code, quantity: 1, direction: "in" } ] },
         headers: auth_headers, as: :json

    assert_response :forbidden
    assert_equal 0, StockMovement.count
  end

  test "view_sales 権限がなければ売上一覧は 403、権限があれば成功" do
    get "/api/v1/sales", params: { employee_id: @employee.id }, headers: auth_headers
    assert_response :forbidden

    get "/api/v1/sales", params: { employee_id: @full_employee.id }, headers: auth_headers
    assert_response :ok
  end
end
