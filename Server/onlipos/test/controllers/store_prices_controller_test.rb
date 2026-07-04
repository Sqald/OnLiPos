require "test_helper"

class StorePricesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "pricetest",
      email: "pricetest@example.com",
      password: "Password1!", password_confirmation: "Password1!",
      first_name: "価格", last_name: "テスト",
      user_type: :individual, confirmed_at: Time.current
    )

    @store  = @user.stores.create!(name: "価格テスト店", ascii_name: "priceteststore")
    @store2 = @user.stores.create!(name: "別店舗", ascii_name: "otherstore")

    @pos = @store.pos_tokens.create!(
      name: "POS1", ascii_name: "pos1",
      password: "PosPass1!", password_confirmation: "PosPass1!"
    )
    @pos.update_columns(token: SecureRandom.hex(32))

    @product  = @user.products.create!(code: "A001", name: "商品A", price: 1000, tax_rate: 10)
    @product2 = @user.products.create!(code: "B002", name: "商品B", price: 2000, tax_rate: 10)

    # edit_prices 権限を持つ従業員
    @editor = @user.employees.create!(code: "E001", name: "価格編集者", pin: "1234")
    @editor.stores << @store
    @editor.employee_permissions.create!(permission: "edit_prices")

    # 権限なし従業員
    @no_perm = @user.employees.create!(code: "E002", name: "権限なし", pin: "9999")
    @no_perm.stores << @store
  end

  # ── GET /api/v1/store_prices ──────────────────────────────────

  test "edit_prices 権限がある担当者は商品一覧を取得できる" do
    get "/api/v1/store_prices",
        params: { employee_id: @editor.id },
        headers: { "Authorization" => "Bearer #{@pos.token}" }

    assert_response :ok
    data = JSON.parse(response.body)
    assert data["success"]
    assert_kind_of Array, data["products"]
    assert_equal 2, data["products"].size
  end

  test "商品ごとに list_price と store_price が返る" do
    Price.create!(store: @store, product: @product, amount: 800)

    get "/api/v1/store_prices",
        params: { employee_id: @editor.id },
        headers: { "Authorization" => "Bearer #{@pos.token}" }

    data = JSON.parse(response.body)
    prod_a = data["products"].find { |p| p["product_id"] == @product.id }
    prod_b = data["products"].find { |p| p["product_id"] == @product2.id }

    assert_equal 1000, prod_a["list_price"]
    assert_equal 800,  prod_a["store_price"]

    assert_equal 2000, prod_b["list_price"]
    assert_nil         prod_b["store_price"]
  end

  test "q パラメータで商品名検索ができる" do
    get "/api/v1/store_prices",
        params: { employee_id: @editor.id, q: "商品A" },
        headers: { "Authorization" => "Bearer #{@pos.token}" }

    data = JSON.parse(response.body)
    assert_equal 1, data["products"].size
    assert_equal @product.id, data["products"].first["product_id"]
  end

  test "edit_prices 権限がない担当者は 403 になる" do
    get "/api/v1/store_prices",
        params: { employee_id: @no_perm.id },
        headers: { "Authorization" => "Bearer #{@pos.token}" }

    assert_response :forbidden
    data = JSON.parse(response.body)
    assert_equal false, data["success"]
  end

  test "他店舗の担当者は 403 になる" do
    other_employee = @user.employees.create!(code: "E003", name: "他店担当者", pin: "5555")
    other_employee.stores << @store2
    other_employee.employee_permissions.create!(permission: "edit_prices")

    get "/api/v1/store_prices",
        params: { employee_id: other_employee.id },
        headers: { "Authorization" => "Bearer #{@pos.token}" }

    assert_response :forbidden
  end

  test "存在しない employee_id は 403 になる" do
    get "/api/v1/store_prices",
        params: { employee_id: 99999 },
        headers: { "Authorization" => "Bearer #{@pos.token}" }

    assert_response :forbidden
  end

  test "不正な POSトークンは 401 になる" do
    get "/api/v1/store_prices",
        params:  { employee_id: @editor.id },
        headers: { "Authorization" => "Bearer this_token_does_not_exist_anywhere" }
    assert_response :unauthorized
  end

  test "カーソルページネーションが動作する" do
    # 合計3商品（セットアップの2 + 追加の1）
    @user.products.create!(code: "C003", name: "商品C", price: 500, tax_rate: 10)

    get "/api/v1/store_prices",
        params: { employee_id: @editor.id, last_id: @product.id },
        headers: { "Authorization" => "Bearer #{@pos.token}" }

    data = JSON.parse(response.body)
    ids = data["products"].map { |p| p["product_id"] }
    assert ids.none? { |id| id <= @product.id }, "last_id 以下の商品が含まれていてはいけない"
  end

  # ── PATCH /api/v1/store_prices ────────────────────────────────

  test "mode=store で店舗売価を upsert できる" do
    patch "/api/v1/store_prices",
          params: { employee_id: @editor.id, product_id: @product.id, mode: "store", amount: 750 },
          headers: { "Authorization" => "Bearer #{@pos.token}" },
          as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    assert data["success"]
    assert_equal "store", data["mode"]
    assert_equal 750, data["amount"]

    price = Price.find_by(store_id: @store.id, product_id: @product.id)
    assert_not_nil price
    assert_equal 750, price.amount
  end

  test "mode=store を再度呼ぶと amount が更新される（upsert）" do
    Price.create!(store: @store, product: @product, amount: 800)

    patch "/api/v1/store_prices",
          params: { employee_id: @editor.id, product_id: @product.id, mode: "store", amount: 600 },
          headers: { "Authorization" => "Bearer #{@pos.token}" },
          as: :json

    assert_response :ok
    assert_equal 600, Price.find_by(store: @store, product: @product).amount
  end

  test "mode=list で Price レコードが削除される（定価に戻る）" do
    Price.create!(store: @store, product: @product, amount: 800)

    patch "/api/v1/store_prices",
          params: { employee_id: @editor.id, product_id: @product.id, mode: "list" },
          headers: { "Authorization" => "Bearer #{@pos.token}" },
          as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    assert data["success"]
    assert_equal "list", data["mode"]
    assert_nil Price.find_by(store: @store, product: @product)
  end

  test "edit_prices 権限がない担当者の PATCH は 403 になる" do
    patch "/api/v1/store_prices",
          params: { employee_id: @no_perm.id, product_id: @product.id, mode: "store", amount: 500 },
          headers: { "Authorization" => "Bearer #{@pos.token}" },
          as: :json

    assert_response :forbidden
    assert_nil Price.find_by(store: @store, product: @product)
  end

  test "別テナントのユーザーの商品は更新できない" do
    other_user    = User.create!(
      login_name: "otheruser", email: "other@example.com",
      password: "Password1!", password_confirmation: "Password1!",
      first_name: "他", last_name: "ユーザー",
      user_type: :individual, confirmed_at: Time.current
    )
    other_product = other_user.products.create!(code: "X999", name: "他社商品", price: 9999, tax_rate: 10)

    patch "/api/v1/store_prices",
          params: { employee_id: @editor.id, product_id: other_product.id, mode: "store", amount: 100 },
          headers: { "Authorization" => "Bearer #{@pos.token}" },
          as: :json

    assert_response :not_found
    assert_nil Price.find_by(store: @store, product: other_product)
  end

  test "amount が負の場合は 422 になる" do
    patch "/api/v1/store_prices",
          params: { employee_id: @editor.id, product_id: @product.id, mode: "store", amount: -1 },
          headers: { "Authorization" => "Bearer #{@pos.token}" },
          as: :json

    assert_response :unprocessable_entity
  end

  test "不正な mode は 400 になる" do
    patch "/api/v1/store_prices",
          params: { employee_id: @editor.id, product_id: @product.id, mode: "invalid" },
          headers: { "Authorization" => "Bearer #{@pos.token}" },
          as: :json

    assert_response :bad_request
  end

  test "mode=store で amount なしは 422 になる" do
    patch "/api/v1/store_prices",
          params: { employee_id: @editor.id, product_id: @product.id, mode: "store" },
          headers: { "Authorization" => "Bearer #{@pos.token}" },
          as: :json

    assert_response :unprocessable_entity
  end

  # ── products/sync の list_price 拡張 ──────────────────────────

  test "products/sync レスポンスに list_price が含まれる" do
    Price.create!(store: @store, product: @product, amount: 800)

    post "/api/v1/products/sync",
         headers: { "Authorization" => "Bearer #{@pos.token}" },
         as: :json

    assert_response :ok
    data     = JSON.parse(response.body)
    prod_a   = data["products"].find { |p| p["id"] == @product.id }

    assert_equal 800,  prod_a["price"],      "price は店舗売価を返すこと"
    assert_equal 1000, prod_a["list_price"], "list_price は定価を返すこと"
  end

  test "店舗売価がない場合、price と list_price は同じ値になる" do
    post "/api/v1/products/sync",
         headers: { "Authorization" => "Bearer #{@pos.token}" },
         as: :json

    data   = JSON.parse(response.body)
    prod_b = data["products"].find { |p| p["id"] == @product2.id }

    assert_equal prod_b["list_price"], prod_b["price"]
  end
end
