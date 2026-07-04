require "test_helper"

# 電子マネー決済区分（emoney: 3）のテスト。
class EmoneyPaymentApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "emoneytest",
      email: "emoneytest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "電マネテスト店舗", ascii_name: "emoneystore")
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @pos_token.update_columns(token: SecureRandom.hex(32))
    @auth = { "Authorization" => "Bearer #{@pos_token.token}" }

    @employee = @user.employees.create!(code: "E001", name: "田中一郎")
    @employee.stores << @store
    @employee.employee_permissions.create!(permission: "view_sales")

    @product = @user.products.create!(code: "P001", name: "商品A", price: 1100, tax_rate: 10)
    StoreStock.create!(store: @store, product: @product, quantity: 100)
  end

  test "電子マネー決済（method: 3）で売上を登録できる" do
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 1100, subtotal_ex_tax: 0, tax_amount: 0 },
           employee_id: @employee.id,
           details: [ { product_id: @product.id, quantity: 1, unit_price: 1100, subtotal: 1100, tax_rate: 10 } ],
           payments: [ { method: 3, amount: 1100, label: "Suica" } ]
         },
         headers: @auth, as: :json

    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])
    assert_equal "emoney", sale.payment_method

    payment = sale.sale_payments.first
    assert_equal "emoney", payment.method
    assert_equal "Suica", payment.label
  end

  test "現金と電子マネーの併用では現金が主たる支払い方法になる" do
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 1100, subtotal_ex_tax: 0, tax_amount: 0 },
           employee_id: @employee.id,
           details: [ { product_id: @product.id, quantity: 1, unit_price: 1100, subtotal: 1100, tax_rate: 10 } ],
           payments: [ { method: 3, amount: 600, label: "iD" }, { method: 0, amount: 500 } ]
         },
         headers: @auth, as: :json

    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])
    assert_equal "cash", sale.payment_method
    assert_equal 600, sale.sale_payments.emoney.sum(:amount)
  end

  test "summary の決済手段別集計に電子マネーが含まれる" do
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 1100, subtotal_ex_tax: 0, tax_amount: 0 },
           employee_id: @employee.id,
           details: [ { product_id: @product.id, quantity: 1, unit_price: 1100, subtotal: 1100, tax_rate: 10 } ],
           payments: [ { method: 3, amount: 1100, label: "楽天Edy" } ]
         },
         headers: @auth, as: :json
    assert_response :created

    get "/api/v1/sales/summary",
        params: { employee_id: @employee.id },
        headers: @auth, as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    assert_equal 1100, data["payment_breakdown"]["emoney"]
  end
end
