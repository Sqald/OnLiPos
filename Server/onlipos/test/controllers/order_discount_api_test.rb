require "test_helper"

# 小計割引（会計全体への金額/％割引）のテスト。
# 明細への按分・税再計算・権限チェック・返品との整合を確認する。
class OrderDiscountApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "odisctest",
      email: "odisctest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "割引テスト店舗", ascii_name: "odiscstore")
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @pos_token.update_columns(token: SecureRandom.hex(32))
    @auth = { "Authorization" => "Bearer #{@pos_token.token}" }

    @employee = @user.employees.create!(code: "E001", name: "田中一郎")
    @employee.stores << @store
    %w[discount refund].each { |p| @employee.employee_permissions.create!(permission: p) }
    @employee2 = @user.employees.create!(code: "E002", name: "佐藤二郎")
    @employee2.stores << @store
    @employee2.employee_permissions.create!(permission: "refund")

    @no_perm = @user.employees.create!(code: "E003", name: "権限なし")
    @no_perm.stores << @store

    @product_a = @user.products.create!(code: "P001", name: "商品A", price: 1100, tax_rate: 10)
    @product_b = @user.products.create!(code: "P002", name: "商品B", price: 1100, tax_rate: 10)
    StoreStock.create!(store: @store, product: @product_a, quantity: 100)
    StoreStock.create!(store: @store, product: @product_b, quantity: 100)
  end

  def post_sale(total:, discount: {}, employee_id: nil, details: nil)
    post "/api/v1/sales",
         params: {
           sale: { total_amount: total, subtotal_ex_tax: 0, tax_amount: 0 }.merge(discount),
           employee_id: employee_id || @employee.id,
           details: details || [
             { product_id: @product_a.id, quantity: 1, unit_price: 1100, subtotal: 1100, tax_rate: 10 },
             { product_id: @product_b.id, quantity: 1, unit_price: 1100, subtotal: 1100, tax_rate: 10 }
           ],
           payments: [ { method: 0, amount: total } ]
         },
         headers: @auth, as: :json
  end

  test "金額割引が明細へ按分され税率別内訳と一致する" do
    # 2200 - 200 = 2000 円請求
    post_sale(
      total: 2000,
      discount: { order_discount_type: "amount", order_discount_value: 200, order_discount_reason: "セール" }
    )
    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])

    assert_equal 200, sale.order_discount_total
    assert_equal "amount", sale.order_discount_type
    assert_equal "セール", sale.order_discount_reason
    assert_equal 200, sale.total_discount

    # 按分: 1100/2200 × 200 = 100 ずつ
    details = sale.saledetails.order(:id)
    assert_equal [ 1000, 1000 ], details.map(&:subtotal)
    assert_equal [ 100, 100 ], details.map(&:discount_amount)
    assert_equal [ 1100, 1100 ], details.map(&:original_unit_price)

    # 税は割引後の額で再計算（2000 × 10/110 = 181）
    breakdown = sale.sale_tax_breakdowns.first
    assert_equal 2000, breakdown.taxable_amount
    assert_equal 181, breakdown.tax_amount
    assert_equal 2000, sale.total_amount
  end

  test "パーセント割引が適用される" do
    # 2200 × 10% = 220 引き → 1980
    post_sale(
      total: 1980,
      discount: { order_discount_type: "percent", order_discount_value: 10 }
    )
    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])

    assert_equal "percent", sale.order_discount_type
    assert_equal 10, sale.order_discount_value
    assert_equal 220, sale.order_discount_total
    assert_equal 1980, sale.saledetails.sum(:subtotal)
    assert_equal 1980, sale.sale_tax_breakdowns.sum(:taxable_amount)
  end

  test "端数が出る按分でも割引合計が一致する" do
    # 3明細 1100×3 = 3300 から 100 円引き → 割り切れない按分
    post_sale(
      total: 3200,
      discount: { order_discount_type: "amount", order_discount_value: 100 },
      details: [
        { product_id: @product_a.id, quantity: 1, unit_price: 1100, subtotal: 1100, tax_rate: 10 },
        { product_id: @product_b.id, quantity: 1, unit_price: 1100, subtotal: 1100, tax_rate: 10 },
        { product_id: @product_a.id, quantity: 1, unit_price: 1100, subtotal: 1100, tax_rate: 10 }
      ]
    )
    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])
    assert_equal 100, sale.saledetails.sum(:discount_amount)
    assert_equal 3200, sale.saledetails.sum(:subtotal)
    assert_equal 3200, sale.sale_tax_breakdowns.sum(:taxable_amount)
  end

  test "discount権限のない担当者は小計割引できない" do
    post_sale(
      total: 2000,
      discount: { order_discount_type: "amount", order_discount_value: 200 },
      employee_id: @no_perm.id
    )
    assert_response :unprocessable_entity
    assert_equal 0, Sale.count
  end

  test "明細合計を超える割引は拒否される" do
    post_sale(
      total: 0,
      discount: { order_discount_type: "amount", order_discount_value: 9999 }
    )
    assert_response :unprocessable_entity
    assert_equal 0, Sale.count
  end

  test "割引後の売上を返品すると割引後の額が返金される" do
    post_sale(
      total: 2000,
      discount: { order_discount_type: "amount", order_discount_value: 200 }
    )
    sale = Sale.find(JSON.parse(response.body)["sale_id"])

    post "/api/v1/refunds",
         params: {
           receipt_number: sale.receipt_number,
           employee_ids: [ @employee.id, @employee2.id ],
           details: [ { saledetail_id: sale.saledetails.order(:id).first.id, quantity: 1 } ]
         },
         headers: @auth, as: :json
    assert_response :created

    refund = Refund.find(JSON.parse(response.body)["refund_id"])
    # 割引後単価 1000 円で返金
    assert_equal 1000, refund.total_amount
  end
end
