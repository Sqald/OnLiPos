require "test_helper"

# 税率別売上集計（API summary / ダッシュボードレポート）のテスト。
# 集計が business_date・status（VOID除外）基準で、インボイス確定値から出ることを確認する。
class TaxSummaryReportTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      login_name: "taxsumtest",
      email: "taxsumtest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "税集計店舗", ascii_name: "taxsumstore")
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @pos_token.update_columns(token: SecureRandom.hex(32))
    @auth = { "Authorization" => "Bearer #{@pos_token.token}" }

    @employee = @user.employees.create!(code: "E001", name: "田中一郎")
    @employee2 = @user.employees.create!(code: "E002", name: "佐藤二郎")
    [ @employee, @employee2 ].each do |e|
      e.stores << @store
      %w[refund view_sales].each { |p| e.employee_permissions.create!(permission: p) }
    end

    @food  = @user.products.create!(code: "F001", name: "食品", price: 1080, tax_rate: 8)
    @goods = @user.products.create!(code: "G001", name: "雑貨", price: 2200, tax_rate: 10)
    StoreStock.create!(store: @store, product: @food, quantity: 100)
    StoreStock.create!(store: @store, product: @goods, quantity: 100)

    # 8%: 1080 / 10%: 2200 の売上
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 3280, subtotal_ex_tax: 0, tax_amount: 0 },
           employee_id: @employee.id,
           details: [
             { product_id: @food.id,  quantity: 1, unit_price: 1080, subtotal: 1080, tax_rate: 8 },
             { product_id: @goods.id, quantity: 1, unit_price: 2200, subtotal: 2200, tax_rate: 10 }
           ],
           payments: [ { method: 0, amount: 3280 } ]
         }, headers: @auth, as: :json
    @sale = Sale.find(JSON.parse(response.body)["sale_id"])

    # 10% 商品を返品
    post "/api/v1/refunds",
         params: {
           receipt_number: @sale.receipt_number,
           employee_ids: [ @employee.id, @employee2.id ],
           details: [ { saledetail_id: @sale.saledetails.find_by(product: @goods).id, quantity: 1 } ]
         }, headers: @auth, as: :json
  end

  test "API summary が税率別の売上・返品控除を返す" do
    get "/api/v1/sales/summary",
        params: { employee_id: @employee.id },
        headers: @auth, as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    tax = data["tax_breakdown"]
    assert_equal 2, tax.size

    row8 = tax.find { |r| r["tax_rate"] == 8 }
    assert_equal 1080, row8["sales_amount"]
    assert_equal 80, row8["sales_tax"]     # 1080 × 8/108 = 80
    assert_equal 0, row8["refund_amount"]
    assert_equal 1080, row8["net_amount"]

    row10 = tax.find { |r| r["tax_rate"] == 10 }
    assert_equal 2200, row10["sales_amount"]
    assert_equal 200, row10["sales_tax"]
    assert_equal 2200, row10["refund_amount"]
    assert_equal 200, row10["refund_tax"]
    assert_equal 0, row10["net_amount"]
    assert_equal 0, row10["net_tax"]
  end

  test "API summary は VOID を売上から除外し別掲する" do
    # もう1件売って取消す
    post "/api/v1/pos_devices/open",
         params: { employee_id: @employee.id, open_date: Date.current.to_s,
                   cash_drawer: { "10000": 1, "5000": 0, "1000": 0, "500": 0, "100": 0, "50": 0, "10": 0, "5": 0, "1": 0 } },
         headers: @auth, as: :json
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 1080, subtotal_ex_tax: 0, tax_amount: 0 },
           employee_id: @employee.id,
           details: [ { product_id: @food.id, quantity: 1, unit_price: 1080, subtotal: 1080, tax_rate: 8 } ],
           payments: [ { method: 0, amount: 1080 } ]
         }, headers: @auth, as: :json
    voided_sale = Sale.find(JSON.parse(response.body)["sale_id"])
    post "/api/v1/sales/#{voided_sale.id}/void",
         params: { employee_ids: [ @employee.id, @employee2.id ], reason: "誤登録" },
         headers: @auth, as: :json
    assert_response :ok

    get "/api/v1/sales/summary",
        params: { employee_id: @employee.id },
        headers: @auth, as: :json
    data = JSON.parse(response.body)

    assert_equal 1, data["sales_count"]          # VOID は含まない
    assert_equal 3280, data["total_amount"]
    assert_equal 1, data["void_count"]
    assert_equal 1080, data["void_total"]
    # VOID 分は税率別集計にも含まれない
    row8 = data["tax_breakdown"].find { |r| r["tax_rate"] == 8 }
    assert_equal 1080, row8["sales_amount"]
  end

  test "ダッシュボードレポートに税率別売上が表示されCSVにも出力される" do
    sign_in @user

    get dashboard_reports_path, params: { from: Date.current.to_s, to: Date.current.to_s }
    assert_response :success
    assert_select "h3", text: "税率別売上"
    assert_select "td", text: "8%"
    assert_select "td", text: "10%"

    get dashboard_reports_path(format: :csv), params: { from: Date.current.to_s, to: Date.current.to_s }
    assert_response :success
    csv = response.body
    assert_includes csv, "--- 税率別売上 ---"
    assert_includes csv, "8,1080,80,0,0,1080,80"
    assert_includes csv, "10,2200,200,2200,200,0,0"
    assert_includes csv, "返品,1,2200"
  end
end
