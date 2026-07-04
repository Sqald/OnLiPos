require "test_helper"

# 税率別内訳（インボイス対応）のテスト。
# - 税率ごとに端数処理1回（明細積み上げではなく会計単位で確定）
# - 内税/外税/非課税、端数処理方式（切捨て/四捨五入/切上げ）
# - 売上と返品の対称性、登録番号の配布
class TaxBreakdownApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "taxtest",
      email: "taxtest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current,
      invoice_registration_number: "T1234567890123"
    )
    @store = @user.stores.create!(name: "税テスト店舗", ascii_name: "taxstore")
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @pos_token.update_columns(token: SecureRandom.hex(32))
    @auth = { "Authorization" => "Bearer #{@pos_token.token}" }

    @employee = @user.employees.create!(code: "E001", name: "田中一郎")
    @employee2 = @user.employees.create!(code: "E002", name: "佐藤二郎")
    [ @employee, @employee2 ].each do |e|
      e.stores << @store
      e.employee_permissions.create!(permission: "refund")
    end

    @food  = @user.products.create!(code: "F001", name: "食品",   price: 999,  tax_rate: 8)
    @goods = @user.products.create!(code: "G001", name: "雑貨",   price: 999,  tax_rate: 10)
    StoreStock.create!(store: @store, product: @food, quantity: 100)
    StoreStock.create!(store: @store, product: @goods, quantity: 100)
  end

  def post_sale(total:, details:)
    post "/api/v1/sales",
         params: {
           sale: { total_amount: total, subtotal_ex_tax: 0, tax_amount: 0 },
           employee_id: @employee.id,
           details: details,
           payments: [ { method: 0, amount: total } ]
         },
         headers: @auth, as: :json
  end

  test "税率混在の売上で税率ごとに1回だけ端数処理された内訳が保存される" do
    # 8%: 999×2 = 1998（税込）、10%: 999×1 = 999（税込）
    post_sale(
      total: 2997,
      details: [
        { product_id: @food.id,  quantity: 2, unit_price: 999, subtotal: 1998, tax_rate: 8 },
        { product_id: @goods.id, quantity: 1, unit_price: 999, subtotal: 999,  tax_rate: 10 }
      ]
    )
    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])

    breakdowns = sale.sale_tax_breakdowns.order(:tax_rate)
    assert_equal 2, breakdowns.size

    b8 = breakdowns.first
    # 1998 × 8/108 = 148.0 → 切捨て 148
    assert_equal 8, b8.tax_rate
    assert_equal 1998, b8.taxable_amount
    assert_equal 148, b8.tax_amount
    assert_equal 1850, b8.amount_ex_tax

    b10 = breakdowns.second
    # 999 × 10/110 = 90.8 → 切捨て 90（明細ごと計算の 91 とは異なる = 会計単位で1回）
    assert_equal 10, b10.tax_rate
    assert_equal 999, b10.taxable_amount
    assert_equal 90, b10.tax_amount

    # ヘッダーは内訳合計と一致する
    assert_equal 148 + 90, sale.tax_amount
    assert_equal 1850 + 909, sale.subtotal_ex_tax
    assert_equal sale.total_amount, breakdowns.sum(:taxable_amount)
  end

  test "四捨五入設定では税額が round される" do
    @user.update!(tax_rounding_method: :round_half_up)

    # 999 × 10/110 = 90.8 → 四捨五入 91
    post_sale(
      total: 999,
      details: [ { product_id: @goods.id, quantity: 1, unit_price: 999, subtotal: 999, tax_rate: 10 } ]
    )
    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])
    assert_equal 91, sale.sale_tax_breakdowns.first.tax_amount
  end

  test "外税商品は税抜合計に税額を加算した額が税込対価になる" do
    exclusive = @user.products.create!(code: "X001", name: "外税商品", price: 1000, tax_rate: 10, tax_type: :exclusive)
    StoreStock.create!(store: @store, product: exclusive, quantity: 10)

    # 税抜 1000 + 税 100 = 請求額 1100
    post_sale(
      total: 1100,
      details: [ { product_id: exclusive.id, quantity: 1, unit_price: 1000, subtotal: 1000, tax_rate: 10, tax_type: 1 } ]
    )
    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])

    breakdown = sale.sale_tax_breakdowns.first
    assert_equal "exclusive", breakdown.tax_type
    assert_equal 1000, breakdown.amount_ex_tax
    assert_equal 100, breakdown.tax_amount
    assert_equal 1100, breakdown.taxable_amount
    assert_equal "exclusive", sale.saledetails.first.tax_type
  end

  test "非課税商品は税額0で計上される" do
    tax_free = @user.products.create!(code: "N001", name: "非課税商品", price: 500, tax_rate: 0, tax_type: :tax_free)
    StoreStock.create!(store: @store, product: tax_free, quantity: 10)

    post_sale(
      total: 500,
      details: [ { product_id: tax_free.id, quantity: 1, unit_price: 500, subtotal: 500, tax_rate: 0, tax_type: 2 } ]
    )
    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])
    breakdown = sale.sale_tax_breakdowns.first
    assert_equal "tax_free", breakdown.tax_type
    assert_equal 0, breakdown.tax_amount
    assert_equal 500, breakdown.taxable_amount
  end

  test "明細合計と会計合計が一致しない売上は拒否される" do
    post_sale(
      total: 1500, # 明細は 999 しかない
      details: [ { product_id: @goods.id, quantity: 1, unit_price: 999, subtotal: 999, tax_rate: 10 } ]
    )
    assert_response :unprocessable_entity
    assert_equal 0, Sale.count
  end

  test "返品にも税率別内訳が保存され売上と対称になる" do
    post_sale(
      total: 2997,
      details: [
        { product_id: @food.id,  quantity: 2, unit_price: 999, subtotal: 1998, tax_rate: 8 },
        { product_id: @goods.id, quantity: 1, unit_price: 999, subtotal: 999,  tax_rate: 10 }
      ]
    )
    sale = Sale.find(JSON.parse(response.body)["sale_id"])

    post "/api/v1/refunds",
         params: {
           receipt_number: sale.receipt_number,
           employee_ids: [ @employee.id, @employee2.id ],
           details: sale.saledetails.map { |d| { saledetail_id: d.id, quantity: d.quantity } }
         },
         headers: @auth, as: :json
    assert_response :created
    refund = Refund.find(JSON.parse(response.body)["refund_id"])

    assert_equal 2997, refund.total_amount
    assert_equal sale.tax_amount, refund.tax_amount
    assert_equal sale.subtotal_ex_tax, refund.subtotal_ex_tax

    refund_breakdowns = refund.refund_tax_breakdowns.order(:tax_rate)
    sale_breakdowns = sale.sale_tax_breakdowns.order(:tax_rate)
    assert_equal sale_breakdowns.map(&:tax_amount), refund_breakdowns.map(&:tax_amount)
    assert_equal sale_breakdowns.map(&:taxable_amount), refund_breakdowns.map(&:taxable_amount)
  end

  test "ログイン応答で登録番号と端数処理方式が配布される" do
    @pos_token.update!(password: "PosPass1!", password_confirmation: "PosPass1!")

    post "/api/v1/pos_devices/login",
         params: { pos: { userName: @user.login_name, storeName: @store.ascii_name, posName: @pos_token.ascii_name, password: "PosPass1!" } },
         as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    assert_equal "T1234567890123", data["invoice_registration_number"]
    assert_equal "round_down", data["tax_rounding_method"]
  end
end
