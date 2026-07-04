require "test_helper"

# レジセッション（開設〜精算）のライフサイクルテスト。
# 開設でセッション作成・Z連番採番、売上/返品/実査の紐付け、
# 精算でスナップショット確定・close を検証する。
class RegisterSessionApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "sessiontest",
      email: "sessiontest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "セッション店舗", ascii_name: "sessionstore")
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @pos_token.update_columns(token: SecureRandom.hex(32))
    @auth = { "Authorization" => "Bearer #{@pos_token.token}" }

    @employee = @user.employees.create!(code: "E001", name: "田中一郎")
    @employee.stores << @store
    @employee2 = @user.employees.create!(code: "E002", name: "佐藤二郎")
    @employee2.stores << @store
    [ @employee, @employee2 ].each { |e| e.employee_permissions.create!(permission: "refund") }

    @product = @user.products.create!(code: "P001", name: "商品A", price: 1100, tax_rate: 10)
    StoreStock.create!(store: @store, product: @product, quantity: 100)
  end

  # 開設（釣銭準備金 50,000 円 = 万札5枚）
  def open_register(date: Date.current)
    post "/api/v1/pos_devices/open",
         params: {
           employee_id: @employee.id, open_date: date.to_s,
           cash_drawer: { "10000": 5, "5000": 0, "1000": 0, "500": 0, "100": 0, "50": 0, "10": 0, "5": 0, "1": 0 }
         },
         headers: @auth, as: :json
  end

  def post_sale(total: 1100)
    post "/api/v1/sales",
         params: {
           sale: { total_amount: total, subtotal_ex_tax: total * 100 / 110, tax_amount: total - total * 100 / 110 },
           employee_id: @employee.id,
           details: [ { product_id: @product.id, product_name: @product.name,
                        quantity: 1, unit_price: total, subtotal: total, tax_rate: 10 } ],
           payments: [ { method: 0, amount: total } ]
         },
         headers: @auth, as: :json
  end

  def close_register(drawer_10000: 5, extra: {})
    post "/api/v1/pos_devices/close_register",
         params: {
           employee_id: @employee.id,
           cash_drawer: { "10000": drawer_10000, "5000": 0, "1000": 0, "500": 0, "100": 1, "50": 1, "10": 5, "5": 0, "1": 0 }
         }.merge(extra),
         headers: @auth, as: :json
  end

  test "レジ開設でセッションが作成されZ連番が採番される" do
    open_register
    assert_response :ok
    data = JSON.parse(response.body)
    assert data["success"]
    assert_equal 1, data["register_session"]["z_number"]
    assert_equal 50_000, data["register_session"]["opening_float"]

    session = RegisterSession.find(data["register_session"]["id"])
    assert session.open?
    assert_equal Date.current, session.business_date
    assert_equal @employee.id, session.opening_employee_id
    assert_equal "open", session.cash_logs.first.log_type
  end

  test "精算前の再開設は拒否される" do
    open_register
    assert_response :ok

    open_register
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["message"], "精算"
  end

  test "売上と返品がセッション・営業日に紐付く" do
    open_register
    session = RegisterSession.open.find_by(pos_token: @pos_token)

    post_sale
    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])
    assert_equal session.id, sale.register_session_id
    assert_equal session.business_date, sale.business_date
    assert_not_nil sale.sold_at

    post "/api/v1/refunds",
         params: {
           receipt_number: sale.receipt_number,
           employee_ids: [ @employee.id, @employee2.id ],
           details: [ { saledetail_id: sale.saledetails.first.id, quantity: 1 } ]
         },
         headers: @auth, as: :json
    assert_response :created
    refund = Refund.find(JSON.parse(response.body)["refund_id"])
    assert_equal session.id, refund.register_session_id
    assert_equal session.business_date, refund.business_date
  end

  test "cash_check_context がセッション基準の理論在高を返す" do
    open_register
    post_sale(total: 1100)

    get "/api/v1/pos_devices/cash_check_context", headers: @auth, as: :json
    assert_response :ok
    data = JSON.parse(response.body)
    # 釣銭準備金 50000 + 現金売上 1100
    assert_equal 51_100, data["expected_amount"]
  end

  test "精算でセッションが閉じスナップショットが確定保存される" do
    open_register
    post_sale(total: 1100)

    # 実査 50000 + 100 + 50 + 50 = 50200 / 理論在高 51100 → 過不足 -900
    close_register(extra: { next_opening_float: 30_000 })
    assert_response :ok
    data = JSON.parse(response.body)
    assert_equal 51_100, data["expected_amount"]
    assert_equal 50_200, data["actual_amount"]
    assert_equal(-900, data["diff_amount"])

    session = RegisterSession.find(data["register_session"]["id"])
    assert session.closed?
    assert_equal 1, session.sales_count
    assert_equal 1100, session.sales_total
    assert_equal 1100, session.cash_sales_total
    assert_equal 51_100, session.expected_cash_amount
    assert_equal 50_200, session.closing_counted_amount
    assert_equal(-900, session.cash_diff_amount)
    assert_equal 30_000, session.next_opening_float
    assert_equal @employee.id, session.closing_employee_id
    assert session.closing_summary["payment_breakdown"].present?

    close_log = session.cash_logs.find_by(log_type: :close)
    assert_equal 51_100, close_log.expected_amount
    assert_equal(-900, close_log.diff_amount)
  end

  test "精算後の再開設でZ連番が増える" do
    open_register
    close_register
    assert_response :ok

    open_register
    assert_response :ok
    assert_equal 2, JSON.parse(response.body)["register_session"]["z_number"]
  end

  test "セッションなし（レガシー）の精算は従来通り動作する" do
    # 開設せずに直接 CashLog を作る旧クライアント相当
    CashLog.create!(
      pos_token: @pos_token, employee: @employee,
      open_date: Date.current, is_start: true,
      yen_10000: 5, yen_5000: 0, yen_1000: 0, yen_500: 0, yen_100: 0,
      yen_50: 0, yen_10: 0, yen_5: 0, yen_1: 0
    )

    close_register
    assert_response :ok
    data = JSON.parse(response.body)
    assert data["success"]
    assert_nil data["register_session"]
    assert_equal 50_000, data["expected_amount"]
  end
end
