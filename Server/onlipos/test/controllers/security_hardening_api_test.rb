require "test_helper"

# API の入力検証・認証まわりのハードニングに対する回帰テスト
class SecurityHardeningApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "sectest",
      email: "sectest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "セキュリティ店", ascii_name: "secstore")
    @pos = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @pos.update_columns(token: SecureRandom.hex(32))
    @employee = @user.employees.create!(code: "E001", name: "田中一郎")
    @employee.stores << @store
    @employee.employee_permissions.create!(permission: "inventory")
    @product = @user.products.create!(code: "4900000000001", name: "商品A", price: 1100, tax_rate: 10)
    @stock = StoreStock.create!(store: @store, product: @product, quantity: 10)
  end

  def auth_headers
    { "Authorization" => "Bearer #{@pos.token}" }
  end

  def post_sale(sale: {}, details: nil, payments: [ { method: 0, amount: 1100 } ])
    details ||= [
      { product_id: @product.id, product_name: @product.name,
        quantity: 1, unit_price: 1100, subtotal: 1100, tax_rate: 10 }
    ]
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 1100, subtotal_ex_tax: 1000, tax_amount: 100 }.merge(sale),
           employee_id: @employee.id,
           details: details,
           payments: payments
         },
         headers: auth_headers,
         as: :json
  end

  # ---- トークン認証 ----

  test "トークンが空のリクエストは 401" do
    get "/api/v1/store_stocks", headers: { "Authorization" => "Bearer " }
    assert_response :unauthorized
  end

  # ---- レシート番号 ----

  test "自端末形式のクライアント採番レシート番号は採用される" do
    receipt = "sectest-secstore-#{@pos.id}-00000099"
    post_sale(sale: { receipt_number: receipt })

    assert_response :created
    assert_equal receipt, JSON.parse(response.body)["receipt_number"]
  end

  test "他端末のレシート番号を指定しても採用されずサーバーで採番される" do
    other_pos_receipt = "victim-store-#{@pos.id + 1000}-00000001"
    post_sale(sale: { receipt_number: other_pos_receipt })

    assert_response :created
    receipt = JSON.parse(response.body)["receipt_number"]
    assert_not_equal other_pos_receipt, receipt
    assert_match(/-#{@pos.id}-\d{8}\z/, receipt)
  end

  # ---- 会計の入力検証 ----

  test "支払合計と会計合計が一致しない場合は 422（500 にならない）" do
    post_sale(payments: [ { method: 0, amount: 1000 } ])

    assert_response :unprocessable_entity
    assert_equal 0, Sale.count
  end

  test "数量 0 の明細は 422" do
    post_sale(
      sale: { total_amount: 0, subtotal_ex_tax: 0, tax_amount: 0 },
      details: [ { product_id: @product.id, quantity: 0, unit_price: 1100, subtotal: 0, tax_rate: 10 } ],
      payments: [ { method: 0, amount: 0 } ]
    )

    assert_response :unprocessable_entity
    assert_equal 0, Sale.count
    assert_equal 10, @stock.reload.quantity
  end

  # ---- 在庫入出荷 ----

  test "入出荷に不正な行が含まれると 422 を返し、在庫は一切変わらない" do
    post "/api/v1/store_stocks/move",
         params: {
           employee_id: @employee.id,
           movements: [
             { jan_code: @product.code, quantity: 5, direction: "in" },
             { jan_code: "NOT_EXIST", quantity: 1, direction: "in" }
           ]
         },
         headers: auth_headers,
         as: :json

    assert_response :unprocessable_entity
    data = JSON.parse(response.body)
    assert_equal false, data["success"]
    assert_includes data["message"], "NOT_EXIST"
    assert_equal 10, @stock.reload.quantity
    assert_equal 0, StockMovement.count
  end

  test "入出荷が正常なら在庫が更新される" do
    post "/api/v1/store_stocks/move",
         params: {
           employee_id: @employee.id,
           movements: [ { jan_code: @product.code, quantity: 3, direction: "out" } ]
         },
         headers: auth_headers,
         as: :json

    assert_response :ok
    assert_equal 7, @stock.reload.quantity
  end

  test "他社の従業員IDでは入出荷できない" do
    other_user = User.create!(
      login_name: "secother", email: "secother@example.com",
      password: "Password1!", password_confirmation: "Password1!",
      first_name: "次郎", last_name: "他社", user_type: :individual,
      confirmed_at: Time.current
    )
    other_emp = other_user.employees.create!(code: "X001", name: "他社担当", is_all_stores: true)

    post "/api/v1/store_stocks/move",
         params: {
           employee_id: other_emp.id,
           movements: [ { jan_code: @product.code, quantity: 1, direction: "in" } ]
         },
         headers: auth_headers,
         as: :json

    assert_response :forbidden
    assert_equal 10, @stock.reload.quantity
  end

  # ---- 冪等キー（再送時の二重計上防止） ----

  def post_sale_with_request_id(request_id, receipt_number: nil)
    post "/api/v1/sales",
         params: {
           client_request_id: request_id,
           sale: { total_amount: 1100, subtotal_ex_tax: 1000, tax_amount: 100, receipt_number: receipt_number },
           employee_id: @employee.id,
           details: [ { product_id: @product.id, quantity: 1, unit_price: 1100, subtotal: 1100, tax_rate: 10 } ],
           payments: [ { method: 0, amount: 1100 } ]
         },
         headers: auth_headers,
         as: :json
  end

  test "同じ client_request_id で再送しても会計は1件だけ登録され、既存の会計が返る" do
    request_id = SecureRandom.uuid
    post_sale_with_request_id(request_id)
    assert_response :created
    first = JSON.parse(response.body)

    # オフライン再送ではローカル採番のレシート番号が付くが、冪等キーで同一会計と判定される
    post_sale_with_request_id(request_id, receipt_number: "sectest-secstore-#{@pos.id}-00000050")
    assert_response :ok
    second = JSON.parse(response.body)

    assert second["success"]
    assert second["duplicate"]
    assert_equal first["sale_id"], second["sale_id"]
    assert_equal first["receipt_number"], second["receipt_number"]
    assert_equal 1, Sale.count
    assert_equal 9, @stock.reload.quantity
  end

  test "client_request_id が異なれば別の会計として登録される" do
    post_sale_with_request_id(SecureRandom.uuid)
    post_sale_with_request_id(SecureRandom.uuid)
    assert_equal 2, Sale.count
  end

  test "client_request_id の形式が不正なら 422" do
    post_sale_with_request_id("bad id!")
    assert_response :unprocessable_entity
    assert_equal 0, Sale.count
  end

  test "レシート番号が重複した場合は 409" do
    receipt = "sectest-secstore-#{@pos.id}-00000077"
    post_sale_with_request_id(SecureRandom.uuid, receipt_number: receipt)
    assert_response :created

    post_sale_with_request_id(SecureRandom.uuid, receipt_number: receipt)
    assert_response :conflict
    assert_equal 1, Sale.count
  end
end
