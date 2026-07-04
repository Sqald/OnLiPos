require "test_helper"

# 点検（X）/ 精算（Z）レポート API のテスト。
class RegisterReportApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "xreporttest",
      email: "xreporttest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "レポート店舗", ascii_name: "reportstore")
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @pos_token.update_columns(token: SecureRandom.hex(32))
    @auth = { "Authorization" => "Bearer #{@pos_token.token}" }

    @employee = @user.employees.create!(code: "E001", name: "田中一郎")
    @employee.stores << @store
    %w[cash_check cash_pickup].each { |p| @employee.employee_permissions.create!(permission: p) }

    @no_perm = @user.employees.create!(code: "E002", name: "権限なし")
    @no_perm.stores << @store

    @food  = @user.products.create!(code: "F001", name: "食品", price: 1080, tax_rate: 8)
    @goods = @user.products.create!(code: "G001", name: "雑貨", price: 1100, tax_rate: 10)
    StoreStock.create!(store: @store, product: @food, quantity: 100)
    StoreStock.create!(store: @store, product: @goods, quantity: 100)

    # 開設 30,000 円
    post "/api/v1/pos_devices/open",
         params: {
           employee_id: @employee.id, open_date: Date.current.to_s,
           cash_drawer: { "10000": 3, "5000": 0, "1000": 0, "500": 0, "100": 0, "50": 0, "10": 0, "5": 0, "1": 0 }
         },
         headers: @auth, as: :json

    # 現金売上 1080 + カード売上 1100
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 1080, subtotal_ex_tax: 0, tax_amount: 0 },
           employee_id: @employee.id,
           details: [ { product_id: @food.id, quantity: 1, unit_price: 1080, subtotal: 1080, tax_rate: 8 } ],
           payments: [ { method: 0, amount: 1080 } ]
         }, headers: @auth, as: :json
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 1100, subtotal_ex_tax: 0, tax_amount: 0 },
           employee_id: @employee.id,
           details: [ { product_id: @goods.id, quantity: 1, unit_price: 1100, subtotal: 1100, tax_rate: 10 } ],
           payments: [ { method: 1, amount: 1100 } ]
         }, headers: @auth, as: :json
  end

  test "Xレポートが決済手段別・税率別の集計を返す" do
    get "/api/v1/pos_devices/register_report",
        params: { employee_id: @employee.id },
        headers: @auth, as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    assert_equal "x", data["report_type"]
    assert_equal 2, data["totals"]["sales_count"]
    assert_equal 2180, data["totals"]["sales_total"]
    assert_equal 1080, data["totals"]["cash_sales_total"]
    # 理論在高 = 30000 + 現金売上 1080
    assert_equal 31_080, data["expected_cash_amount"]

    payment = data["breakdown"]["payment_breakdown"]
    assert_equal 1080, payment["cash"]
    assert_equal 1100, payment["card"]

    tax = data["breakdown"]["tax_breakdown"]
    rates = tax.map { |t| t["tax_rate"] }
    assert_equal [ 8, 10 ], rates
    assert_equal 1080, tax.first["sales_amount"]
  end

  test "精算後にZレポートをz_number指定で再取得できる" do
    post "/api/v1/pos_devices/close_register",
         params: {
           employee_id: @employee.id,
           cash_drawer: { "10000": 3, "5000": 0, "1000": 1, "500": 0, "100": 0, "50": 1, "10": 3, "5": 0, "1": 0 }
         },
         headers: @auth, as: :json
    assert_response :ok
    z_number = JSON.parse(response.body)["register_session"]["z_number"]

    get "/api/v1/pos_devices/register_report",
        params: { employee_id: @employee.id, z_number: z_number },
        headers: @auth, as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    assert_equal "z", data["report_type"]
    assert_equal 2, data["totals"]["sales_count"]
    assert_equal 31_080, data["expected_cash_amount"]
    assert_equal 31_080, data["closing_counted_amount"]
    assert_equal 0, data["cash_diff_amount"]
    assert data["breakdown"]["payment_breakdown"].present?
  end

  test "cash_check権限のない従業員は403" do
    get "/api/v1/pos_devices/register_report",
        params: { employee_id: @no_perm.id },
        headers: @auth, as: :json
    assert_response :forbidden
  end

  test "セッションが開いていない場合の点検は422" do
    post "/api/v1/pos_devices/close_register",
         params: {
           employee_id: @employee.id,
           cash_drawer: { "10000": 3, "5000": 0, "1000": 1, "500": 0, "100": 0, "50": 1, "10": 3, "5": 0, "1": 0 }
         },
         headers: @auth, as: :json

    get "/api/v1/pos_devices/register_report",
        params: { employee_id: @employee.id },
        headers: @auth, as: :json
    assert_response :unprocessable_entity
  end
end
