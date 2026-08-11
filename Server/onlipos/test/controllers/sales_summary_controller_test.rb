require "test_helper"

class SalesSummaryControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "summarytest",
      email: "summarytest@example.com",
      password: "Password1!", password_confirmation: "Password1!",
      first_name: "集計", last_name: "テスト",
      user_type: :individual, confirmed_at: Time.current
    )

    @store  = @user.stores.create!(name: "集計テスト店",  ascii_name: "summarystore")
    @store2 = @user.stores.create!(name: "別店舗",        ascii_name: "summarystore2")

    @pos = @store.pos_tokens.create!(
      name: "POS1", ascii_name: "pos1",
      password: "PosPass1!", password_confirmation: "PosPass1!"
    )
    @pos.update_columns(token: SecureRandom.hex(32))

    @product1 = @user.products.create!(code: "SP001", name: "商品1", price: 1000, tax_rate: 10)
    @product2 = @user.products.create!(code: "SP002", name: "商品2", price: 2000, tax_rate: 10)

    @viewer = @user.employees.create!(code: "SV001", name: "閲覧者", pin: "1234")
    @viewer.stores << @store
    @viewer.employee_permissions.create!(permission: "view_sales")

    @no_perm = @user.employees.create!(code: "SN001", name: "権限なし", pin: "5678")
    @no_perm.stores << @store

    create_test_sales
  end

  def create_test_sales
    sale1 = Sale.create!(
      user: @user, store: @store, pos_token: @pos,
      total_amount: 1000, payment_method: :cash,
      subtotal_ex_tax: 909, tax_amount: 91
    )
    sale1.saledetails.create!(
      product: @product1, product_name: "商品1",
      quantity: 1, unit_price: 1000, subtotal: 1000,
      tax_rate: 10, tax_amount: 91, discount_amount: 0
    )
    sale1.sale_payments.create!(method: :cash, amount: 1000)

    sale2 = Sale.create!(
      user: @user, store: @store, pos_token: @pos,
      total_amount: 4000, payment_method: :card,
      subtotal_ex_tax: 3636, tax_amount: 364
    )
    sale2.saledetails.create!(
      product: @product2, product_name: "商品2",
      quantity: 2, unit_price: 2000, subtotal: 4000,
      tax_rate: 10, tax_amount: 364, discount_amount: 0
    )
    sale2.sale_payments.create!(method: :card, amount: 4000)
  end

  def today_str
    Date.current.to_s
  end

  def auth_header
    { "Authorization" => "Bearer #{@pos.token}" }
  end

  # ── 正常系 ───────────────────────────────────────────────────────

  test "view_sales 権限があれば集計を取得できる" do
    get "/api/v1/sales/summary",
        params:  { employee_id: @viewer.id, from: today_str, to: today_str },
        headers: auth_header

    assert_response :ok
    data = JSON.parse(response.body)
    assert data["success"]
    assert_equal 2,    data["sales_count"]
    assert_equal 5000, data["total_amount"]
  end

  test "payment_breakdown が sale_payments 基準で返る" do
    get "/api/v1/sales/summary",
        params:  { employee_id: @viewer.id, from: today_str, to: today_str },
        headers: auth_header

    data      = JSON.parse(response.body)
    breakdown = data["payment_breakdown"]
    assert_equal 1000, breakdown["cash"]
    assert_equal 4000, breakdown["card"]
    assert_equal 0,    breakdown["barcode"]
  end

  test "top_products が売上金額降順で返る" do
    get "/api/v1/sales/summary",
        params:  { employee_id: @viewer.id, from: today_str, to: today_str },
        headers: auth_header

    data = JSON.parse(response.body)
    top  = data["top_products"]
    assert_kind_of Array, top
    assert_not_empty top
    assert_equal "商品2", top.first["product_name"]
    assert_equal 2,       top.first["quantity"]
    assert_equal 4000,    top.first["amount"]
  end

  test "period フィールドが返る" do
    get "/api/v1/sales/summary",
        params:  { employee_id: @viewer.id, from: "2026-06-01", to: "2026-06-30" },
        headers: auth_header

    data = JSON.parse(response.body)
    assert_equal "2026-06-01", data["period"]["from"]
    assert_equal "2026-06-30", data["period"]["to"]
  end

  test "daily が返る" do
    get "/api/v1/sales/summary",
        params:  { employee_id: @viewer.id, from: today_str, to: today_str },
        headers: auth_header

    data = JSON.parse(response.body)
    assert_kind_of Array, data["daily"]
    assert_not_empty data["daily"]
    first_day = data["daily"].first
    assert first_day.key?("date")
    assert first_day.key?("count")
    assert first_day.key?("amount")
  end

  test "customer_segment_breakdown が客層キー別に集計される" do
    Sale.create!(
      user: @user, store: @store, pos_token: @pos,
      total_amount: 500, payment_method: :cash,
      subtotal_ex_tax: 455, tax_amount: 45,
      customer_gender: :female, customer_age_group: :twenties
    )

    get "/api/v1/sales/summary",
        params:  { employee_id: @viewer.id, from: today_str, to: today_str },
        headers: auth_header

    data = JSON.parse(response.body)
    breakdown = data["customer_segment_breakdown"]
    assert_kind_of Array, breakdown
    row = breakdown.find { |r| r["gender"] == "female" && r["age_group"] == "twenties" }
    assert row, "客層キー別集計に female/twenties が含まれること"
    assert_equal 1,   row["count"]
    assert_equal 500, row["amount"]
  end

  test "refund_count と refund_total が返る" do
    get "/api/v1/sales/summary",
        params:  { employee_id: @viewer.id, from: today_str, to: today_str },
        headers: auth_header

    data = JSON.parse(response.body)
    assert data.key?("refund_count")
    assert data.key?("refund_total")
    assert_equal 0, data["refund_count"]
    assert_equal 0, data["refund_total"]
  end

  # ── 店舗スコープ ─────────────────────────────────────────────────

  test "他店舗の売上は集計に含まれない" do
    other_pos = @store2.pos_tokens.create!(
      name: "POS2", ascii_name: "pos2",
      password: "PosPass2!", password_confirmation: "PosPass2!"
    )
    other_pos.update_columns(token: SecureRandom.hex(32))

    other_sale = Sale.create!(
      user: @user, store: @store2, pos_token: other_pos,
      total_amount: 9999, payment_method: :cash,
      subtotal_ex_tax: 9090, tax_amount: 909
    )
    other_sale.sale_payments.create!(method: :cash, amount: 9999)

    get "/api/v1/sales/summary",
        params:  { employee_id: @viewer.id, from: today_str, to: today_str },
        headers: auth_header

    data = JSON.parse(response.body)
    assert_equal 5000, data["total_amount"], "自店舗の売上のみ集計されること"
    assert_equal 2,    data["sales_count"]
  end

  # ── 権限拒否 ─────────────────────────────────────────────────────

  test "view_sales 権限がない担当者は 403 になる" do
    get "/api/v1/sales/summary",
        params:  { employee_id: @no_perm.id, from: today_str, to: today_str },
        headers: auth_header

    assert_response :forbidden
    data = JSON.parse(response.body)
    assert_equal false, data["success"]
    assert_equal "view_sales", data["required_permission"]
  end

  test "他店舗の担当者は 403 になる（店舗アクセス権限なし）" do
    other_emp = @user.employees.create!(code: "SO001", name: "他店担当", pin: "9999")
    other_emp.stores << @store2
    other_emp.employee_permissions.create!(permission: "view_sales")

    get "/api/v1/sales/summary",
        params:  { employee_id: other_emp.id, from: today_str, to: today_str },
        headers: auth_header

    assert_response :forbidden
  end

  test "存在しない employee_id は 403 になる" do
    get "/api/v1/sales/summary",
        params:  { employee_id: 99999, from: today_str, to: today_str },
        headers: auth_header

    assert_response :forbidden
  end

  # ── バリデーション ────────────────────────────────────────────────

  test "不正な日付は 400 になる" do
    get "/api/v1/sales/summary",
        params:  { employee_id: @viewer.id, from: "not-a-date", to: "2026-06-30" },
        headers: auth_header

    assert_response :bad_request
  end

  test "不正な POS トークンは 401 になる" do
    get "/api/v1/sales/summary",
        params:  { employee_id: @viewer.id, from: today_str, to: today_str },
        headers: { "Authorization" => "Bearer invalid_token_here" }

    assert_response :unauthorized
  end
end
