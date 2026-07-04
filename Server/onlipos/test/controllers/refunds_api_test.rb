require "test_helper"

# 部分返品の整合性テスト:
# - 在庫戻しは返品明細の数量分のみ（全量戻しの廃止）
# - 残数量の範囲で複数回返品できる
# - 返品に税情報・営業日が記録される
class RefundsApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "refundtest",
      email: "refundtest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "返品テスト店舗", ascii_name: "refundstore")
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @pos_token.update_columns(token: SecureRandom.hex(32))

    @employee1 = @user.employees.create!(code: "E001", name: "田中一郎")
    @employee2 = @user.employees.create!(code: "E002", name: "佐藤二郎")
    [ @employee1, @employee2 ].each do |e|
      e.stores << @store
      e.employee_permissions.create!(permission: "refund")
    end

    @product = @user.products.create!(code: "P001", name: "商品A", price: 1100, tax_rate: 10)
    @stock = StoreStock.create!(store: @store, product: @product, quantity: 100)

    # 3個売れた会計を作る（在庫 100 -> 97 相当。ここでは直接生成）
    @sale = Sale.create!(
      user: @user, store: @store, pos_token: @pos_token,
      total_amount: 3300, payment_method: :cash,
      subtotal_ex_tax: 3000, tax_amount: 300
    )
    @saledetail = @sale.saledetails.create!(
      product: @product, product_name: @product.name,
      quantity: 3, unit_price: 1100, subtotal: 3300,
      tax_rate: 10, tax_amount: 300
    )
    @sale.sale_payments.create!(method: :cash, amount: 3300)
  end

  def post_refund(quantity:)
    post "/api/v1/refunds",
         params: {
           receipt_number: @sale.receipt_number,
           employee_ids: [ @employee1.id, @employee2.id ],
           details: [ { saledetail_id: @saledetail.id, quantity: quantity } ]
         },
         headers: { "Authorization" => "Bearer #{@pos_token.token}" },
         as: :json
  end

  test "部分返品では返品数量分だけ在庫が戻る" do
    post_refund(quantity: 1)
    assert_response :created

    assert_equal 101, @stock.reload.quantity
    movement = StockMovement.where(reason: "return", sale: @sale).last
    assert_equal 1, movement.quantity_change
  end

  test "返品に税情報と営業日が記録される" do
    post_refund(quantity: 1)
    assert_response :created

    refund = Refund.find(JSON.parse(response.body)["refund_id"])
    assert_equal 1100, refund.total_amount
    assert_equal 1000, refund.subtotal_ex_tax
    assert_equal 100, refund.tax_amount
    assert_equal Date.current, refund.business_date
    assert_not_nil refund.refunded_at

    detail = refund.refund_details.first
    assert_equal 10, detail.tax_rate
    assert_equal 100, detail.tax_amount
  end

  test "残数量の範囲で複数回返品できる" do
    post_refund(quantity: 1)
    assert_response :created

    post_refund(quantity: 2)
    assert_response :created

    assert_equal 103, @stock.reload.quantity
    assert_equal 2, @sale.refunds.count
    assert_equal 3300, @sale.refunds.sum(:total_amount)
  end

  test "返品可能数量を超える返品は拒否される" do
    post_refund(quantity: 2)
    assert_response :created

    post_refund(quantity: 2)
    assert_response :unprocessable_entity
    message = JSON.parse(response.body)["message"]
    assert_includes message, "返品可能数量"

    # 在庫・返品は最初の1回分のみ
    assert_equal 102, @stock.reload.quantity
    assert_equal 1, @sale.refunds.count
  end

  test "sale_by_receipt が返品済み数量と残数量を返す" do
    post_refund(quantity: 1)
    assert_response :created

    get "/api/v1/refunds/sale_by_receipt",
        params: { receipt_number: @sale.receipt_number },
        headers: { "Authorization" => "Bearer #{@pos_token.token}" }

    assert_response :ok
    data = JSON.parse(response.body)
    detail = data["details"].first
    assert_equal 1, detail["refunded_quantity"]
    assert_equal 2, detail["refundable_quantity"]
    assert_equal false, data["sale"]["refunded"]

    post_refund(quantity: 2)
    get "/api/v1/refunds/sale_by_receipt",
        params: { receipt_number: @sale.receipt_number },
        headers: { "Authorization" => "Bearer #{@pos_token.token}" }
    assert_equal true, JSON.parse(response.body)["sale"]["refunded"]
  end
end
