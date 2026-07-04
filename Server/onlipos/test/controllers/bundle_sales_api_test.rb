require "test_helper"

# セット商品（バンドル）売上の価格按分テスト。
# バンドル販売価格を構成品の定価比で按分し、明細合計が売上合計と一致することを確認する。
class BundleSalesApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "bundletest",
      email: "bundletest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "テスト店舗", ascii_name: "bundleteststore")
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @pos_token.update_columns(token: SecureRandom.hex(32))

    @product_a = @user.products.create!(code: "BP001", name: "構成品A", price: 300, tax_rate: 10)
    @product_b = @user.products.create!(code: "BP002", name: "構成品B", price: 700, tax_rate: 10)
    StoreStock.create!(store: @store, product: @product_a, quantity: 100)
    StoreStock.create!(store: @store, product: @product_b, quantity: 100)

    # 定価合計 1000 円のセットを 999 円で販売する（端数が出るケース）
    @bundle = @user.product_bundles.create!(code: "SET001", name: "お得セット", price: 999)
    @bundle.product_bundle_items.create!(product: @product_a, quantity: 1)
    @bundle.product_bundle_items.create!(product: @product_b, quantity: 1)
  end

  def post_sale(total:, details:)
    post "/api/v1/sales",
         params: {
           sale: { total_amount: total, subtotal_ex_tax: 0, tax_amount: 0 },
           details: details,
           payments: [ { method: 0, amount: total } ]
         },
         headers: { "Authorization" => "Bearer #{@pos_token.token}" },
         as: :json
  end

  test "バンドル販売価格が構成品定価比で按分され合計が一致する" do
    post_sale(
      total: 999,
      details: [ { bundle_code: "SET001", quantity: 1, unit_price: 999, subtotal: 999 } ]
    )

    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])
    details = sale.saledetails.order(:id)

    assert_equal 2, details.size
    # 300/1000 × 999 = 299.7 → 299、端数は最後の構成品へ
    assert_equal 299, details[0].subtotal
    assert_equal 700, details[1].subtotal
    assert_equal 999, details.sum(&:subtotal)
    assert_equal sale.total_amount, details.sum(&:subtotal)
  end

  test "subtotal未指定の場合はマスタのバンドル価格で按分する" do
    post_sale(
      total: 999,
      details: [ { bundle_code: "SET001", quantity: 1 } ]
    )

    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])
    assert_equal 999, sale.saledetails.sum(:subtotal)
  end

  test "バンドル数量2の場合も按分合計が販売価格と一致し在庫が数量分減る" do
    post_sale(
      total: 1998,
      details: [ { bundle_code: "SET001", quantity: 2, unit_price: 999, subtotal: 1998 } ]
    )

    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])
    assert_equal 1998, sale.saledetails.sum(:subtotal)

    assert_equal 98, StoreStock.find_by(store: @store, product: @product_a).quantity
    assert_equal 98, StoreStock.find_by(store: @store, product: @product_b).quantity
  end

  test "店舗別のバンドル値引き価格（クライアント送信subtotal）が優先される" do
    post_sale(
      total: 900,
      details: [ { bundle_code: "SET001", quantity: 1, unit_price: 900, subtotal: 900 } ]
    )

    assert_response :created
    sale = Sale.find(JSON.parse(response.body)["sale_id"])
    details = sale.saledetails.order(:id)
    # 300/1000 × 900 = 270、残り 630
    assert_equal [ 270, 630 ], details.map(&:subtotal)
  end
end
