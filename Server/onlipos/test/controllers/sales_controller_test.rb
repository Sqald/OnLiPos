require "test_helper"

class SalesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "salestest",
      email: "salestest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "テスト店舗", ascii_name: "salesteststore")
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    # セキュアトークン生成
    @pos_token.update_columns(token: SecureRandom.hex(32))
    @employee = @user.employees.create!(code: "E001", name: "田中一郎")
    @employee.stores << @store
    @product = @user.products.create!(code: "P001", name: "商品A", price: 1000, tax_rate: 10)
    StoreStock.create!(store: @store, product: @product, quantity: 100)
  end

  # ---- 担当者紐付け ----

  test "売上作成時に employee_id が保存される" do
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 1100, subtotal_ex_tax: 1000, tax_amount: 100 },
           employee_id: @employee.id,
           details: [
             { product_id: @product.id, product_name: @product.name,
               quantity: 1, unit_price: 1100, subtotal: 1100, tax_rate: 10, tax_amount: 100 }
           ],
           payments: [ { method: 0, amount: 1100 } ]
         },
         headers: { "Authorization" => "Bearer #{@pos_token.token}" },
         as: :json

    assert_response :created
    data = JSON.parse(response.body)
    assert data["success"]

    sale = Sale.find(data["sale_id"])
    assert_equal @employee.id, sale.employee_id
  end

  test "employee_id が存在しない場合も売上を作成できる" do
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 1100, subtotal_ex_tax: 1000, tax_amount: 100 },
           details: [
             { product_id: @product.id, product_name: @product.name,
               quantity: 1, unit_price: 1100, subtotal: 1100, tax_rate: 10, tax_amount: 100 }
           ],
           payments: [ { method: 0, amount: 1100 } ]
         },
         headers: { "Authorization" => "Bearer #{@pos_token.token}" },
         as: :json

    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])
    assert_nil sale.employee_id
  end

  # ---- 割引追跡 ----

  test "original_unit_price を送ると discount_amount が計算・保存される" do
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 880, subtotal_ex_tax: 800, tax_amount: 80 },
           employee_id: @employee.id,
           details: [
             { product_id: @product.id, product_name: @product.name,
               quantity: 1, unit_price: 880, subtotal: 880,
               tax_rate: 10, tax_amount: 80,
               original_unit_price: 1100 }
           ],
           payments: [ { method: 0, amount: 880 } ]
         },
         headers: { "Authorization" => "Bearer #{@pos_token.token}" },
         as: :json

    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])
    detail = sale.saledetails.first

    assert_equal 1100, detail.original_unit_price
    assert_equal 220,  detail.discount_amount  # (1100 - 880) * 1
    assert_equal 220,  sale.total_discount
  end

  test "original_unit_price が unit_price より低い場合は discount_amount = 0" do
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 1100, subtotal_ex_tax: 1000, tax_amount: 100 },
           employee_id: @employee.id,
           details: [
             { product_id: @product.id, product_name: @product.name,
               quantity: 1, unit_price: 1100, subtotal: 1100,
               tax_rate: 10, tax_amount: 100,
               original_unit_price: 900 }  # 値上げなので割引なし
           ],
           payments: [ { method: 0, amount: 1100 } ]
         },
         headers: { "Authorization" => "Bearer #{@pos_token.token}" },
         as: :json

    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])
    assert_equal 0, sale.total_discount
    assert_equal 0, sale.saledetails.first.discount_amount
  end

  test "支払い合計が sale total と一致しない場合は 500 エラー" do
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 1100 },
           details: [],
           payments: [ { method: 0, amount: 500 } ]  # 合計不一致
         },
         headers: { "Authorization" => "Bearer #{@pos_token.token}" },
         as: :json

    assert_response :internal_server_error
  end

  test "discount_reason を送ると saledetail に保存される" do
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 880, subtotal_ex_tax: 800, tax_amount: 80 },
           employee_id: @employee.id,
           details: [
             { product_id: @product.id, product_name: @product.name,
               quantity: 1, unit_price: 880, subtotal: 880,
               tax_rate: 10, tax_amount: 80,
               original_unit_price: 1100,
               discount_reason: "賞味期限値引き" }
           ],
           payments: [ { method: 0, amount: 880 } ]
         },
         headers: { "Authorization" => "Bearer #{@pos_token.token}" },
         as: :json

    assert_response :created
    detail = Sale.find(JSON.parse(response.body)["sale_id"]).saledetails.first
    assert_equal "賞味期限値引き", detail.discount_reason
    assert_equal 220, detail.discount_amount
  end

  # ---- 客層キー ----

  test "customer_gender / customer_age_group を送ると sale に保存される" do
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 1100, subtotal_ex_tax: 1000, tax_amount: 100,
                   customer_gender: "female", customer_age_group: "thirties" },
           employee_id: @employee.id,
           details: [
             { product_id: @product.id, product_name: @product.name,
               quantity: 1, unit_price: 1100, subtotal: 1100, tax_rate: 10, tax_amount: 100 }
           ],
           payments: [ { method: 0, amount: 1100 } ]
         },
         headers: { "Authorization" => "Bearer #{@pos_token.token}" },
         as: :json

    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])
    assert_equal "female", sale.customer_gender
    assert_equal "thirties", sale.customer_age_group
  end

  test "customer_gender / customer_age_group を送らなくても売上を作成できる" do
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 1100, subtotal_ex_tax: 1000, tax_amount: 100 },
           employee_id: @employee.id,
           details: [
             { product_id: @product.id, product_name: @product.name,
               quantity: 1, unit_price: 1100, subtotal: 1100, tax_rate: 10, tax_amount: 100 }
           ],
           payments: [ { method: 0, amount: 1100 } ]
         },
         headers: { "Authorization" => "Bearer #{@pos_token.token}" },
         as: :json

    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])
    assert_nil sale.customer_gender
    assert_nil sale.customer_age_group
  end

  # ---- 量り売り（計量）商品 ----

  test "量り売り商品は weight_grams が saledetail に保存される" do
    scale_product = @user.products.create!(code: "P002", name: "量り売り商品", price: 500, tax_rate: 8, sold_by_weight: true)

    post "/api/v1/sales",
         params: {
           sale: { total_amount: 250, subtotal_ex_tax: 232, tax_amount: 18 },
           employee_id: @employee.id,
           details: [
             { product_id: scale_product.id, product_name: scale_product.name,
               quantity: 1, unit_price: 500, subtotal: 250,
               tax_rate: 8, tax_amount: 18, weight_grams: 500 }
           ],
           payments: [ { method: 0, amount: 250 } ]
         },
         headers: { "Authorization" => "Bearer #{@pos_token.token}" },
         as: :json

    assert_response :created
    detail = Sale.find(JSON.parse(response.body)["sale_id"]).saledetails.first
    assert_equal 500, detail.weight_grams
    assert_equal 250, detail.subtotal
  end

  test "量り売り商品で weight_grams を送らない場合は 422 エラー" do
    scale_product = @user.products.create!(code: "P003", name: "量り売り商品2", price: 500, tax_rate: 8, sold_by_weight: true)

    post "/api/v1/sales",
         params: {
           sale: { total_amount: 250, subtotal_ex_tax: 232, tax_amount: 18 },
           employee_id: @employee.id,
           details: [
             { product_id: scale_product.id, product_name: scale_product.name,
               quantity: 1, unit_price: 500, subtotal: 250,
               tax_rate: 8, tax_amount: 18 }
           ],
           payments: [ { method: 0, amount: 250 } ]
         },
         headers: { "Authorization" => "Bearer #{@pos_token.token}" },
         as: :json

    assert_response :unprocessable_entity
    data = JSON.parse(response.body)
    assert_not data["success"]
  end

  test "unit_price が負の場合は 422 エラー" do
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 0, subtotal_ex_tax: 0, tax_amount: 0 },
           employee_id: @employee.id,
           details: [
             { product_id: @product.id, product_name: @product.name,
               quantity: 1, unit_price: -100, subtotal: -100,
               tax_rate: 10, tax_amount: -9 }
           ],
           payments: [ { method: 0, amount: 0 } ]
         },
         headers: { "Authorization" => "Bearer #{@pos_token.token}" },
         as: :json

    assert_response :unprocessable_entity
    data = JSON.parse(response.body)
    assert_not data["success"]
  end
end
