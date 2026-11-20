require "test_helper"

class DashboardAnalyticsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      login_name: "analyticsctl", email: "analyticsctl@example.com",
      password: "Password1!", password_confirmation: "Password1!",
      first_name: "太郎", last_name: "分析", user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "分析店舗", ascii_name: "anstore")
    @employee = @user.employees.create!(code: "A001", name: "分析花子")
    @product = @user.products.create!(code: "AP1", name: "分析商品", price: 1200)
    sale = Sale.create!(user: @user, store: @store, employee: @employee, total_amount: 2400, payment_method: :card)
    sale.saledetails.create!(product: @product, product_name: @product.name, quantity: 2, unit_price: 1200,
                             subtotal: 2400, tax_rate: 10)
    sign_in @user
  end

  test "既定（直近30日・日別）で表示できる" do
    get dashboard_analytics_path
    assert_response :success
    assert_select "h2", "売上分析"
    assert_select "svg.viz-svg"
    assert_match "¥2,400", response.body
  end

  test "すべての軸・指標・クロス集計で表示できる" do
    dims = SalesAnalysis::DIMENSIONS.keys
    SalesAnalysis::METRICS.each_key do |metric|
      dims.each do |row|
        get dashboard_analytics_path, params: { row: row, metric: metric }
        assert_response :success, "row=#{row} metric=#{metric}"
      end
    end
    dims.each do |row|
      dims.each do |col|
        get dashboard_analytics_path, params: { row: row, col: col, metric: "amount" }
        assert_response :success, "row=#{row} col=#{col}"
      end
    end
  end

  test "従業員×商品のクロス集計に担当者と商品が出る" do
    get dashboard_analytics_path, params: { row: "employee", col: "product" }
    assert_response :success
    assert_select "table.an-pivot th", text: /分析花子/
    assert_select "table.an-pivot th", text: /分析商品/
  end

  test "CSVでダウンロードできる" do
    get dashboard_analytics_path(format: :csv), params: { row: "store" }
    assert_response :success
    assert_match "分析店舗", response.body
    assert_match "2400", response.body
  end

  test "不正な日付でもエラーにならない" do
    get dashboard_analytics_path, params: { from: "abc", to: "2026-99-99" }
    assert_response :success
  end

  test "販売履歴のある従業員を削除しようとすると案内が出て残る" do
    delete dashboard_employee_path(@employee)
    assert_redirected_to dashboard_employees_path
    assert Employee.exists?(@employee.id)
    assert_match "削除できません", flash[:alert]
  end

  test "販売履歴のある商品・店舗は削除できない" do
    delete dashboard_product_path(@product)
    assert Product.exists?(@product.id)
    assert_match "廃盤", flash[:alert]

    delete dashboard_store_path(@store)
    assert Store.exists?(@store.id)
    assert_match "削除できません", flash[:alert]
  end
end
