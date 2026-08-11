require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      login_name: "reporttest",
      email: "reporttest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "レポート",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "レポート店舗", ascii_name: "reportstore")
    @employee = @user.employees.create!(code: "R001", name: "レポート太郎")
    @employee.stores << @store

    # 現金売上を1件作成
    sale_cash = Sale.create!(
      user: @user, store: @store, employee: @employee,
      total_amount: 1100, subtotal_ex_tax: 1000, tax_amount: 100,
      payment_method: :cash
    )
    sale_cash.sale_payments.create!(method: 0, amount: 1100)

    # カード売上を1件作成
    sale_card = Sale.create!(
      user: @user, store: @store, employee: @employee,
      total_amount: 2200, subtotal_ex_tax: 2000, tax_amount: 200,
      payment_method: :card
    )
    sale_card.sale_payments.create!(method: 1, amount: 2200)

    sign_in @user
  end

  test "レポートページにアクセスできる" do
    get dashboard_reports_path
    assert_response :success
  end

  test "検索条件なしではデータが表示されない" do
    get dashboard_reports_path
    assert_select ".empty-message"
  end

  test "期間を指定すると売上データが表示される" do
    get dashboard_reports_path, params: {
      from: Date.current.to_s,
      to: Date.current.to_s
    }
    assert_response :success
    assert_select "h3", text: "支払い方法別集計"
    assert_select "h3", text: "担当者別売上"
  end

  test "支払い方法別集計が正しく算出される" do
    get dashboard_reports_path, params: {
      from: Date.current.to_s,
      to: Date.current.to_s
    }
    assert_response :success
    assert_select "td", text: "現金"
    assert_select "td", text: "カード"
    assert_match(/1,100/, response.body)
    assert_match(/2,200/, response.body)
  end

  test "担当者別売上が表示される" do
    get dashboard_reports_path, params: {
      from: Date.current.to_s,
      to: Date.current.to_s
    }
    assert_response :success
    assert_select "td", text: @employee.name
    assert_match(/3,300/, response.body)
  end

  test "客層キー別売上が表示される" do
    sale_segment = Sale.create!(
      user: @user, store: @store, employee: @employee,
      total_amount: 500, subtotal_ex_tax: 455, tax_amount: 45,
      payment_method: :cash, customer_gender: :male, customer_age_group: :forties
    )
    sale_segment.sale_payments.create!(method: 0, amount: 500)

    get dashboard_reports_path, params: {
      from: Date.current.to_s,
      to: Date.current.to_s
    }
    assert_response :success
    assert_select "h3", text: "客層キー別売上"
    assert_select "td", text: "男性"
    assert_select "td", text: "40代"
  end
end
