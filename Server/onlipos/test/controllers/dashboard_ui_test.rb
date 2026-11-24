require "test_helper"

# ダッシュボードの枠（メニュー・見出し・フッター）と、使いやすさに関わる初期表示の確認
class DashboardUiTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(login_name: "uiowner", email: "ui@example.com", password: "Password1!", password_confirmation: "Password1!",
                         first_name: "花子", last_name: "見本", user_type: :individual, confirmed_at: Time.current)
  end

  def member(role)
    User.create!(owner_id: @user.id, role: role, login_name: "ui#{role}", email: "#{role}@example.com", password: "Password1!", password_confirmation: "Password1!",
                 first_name: "次郎", last_name: "閲覧", user_type: :individual, confirmed_at: Time.current)
  end

  # 引数なしで開ける一覧・登録画面すべて
  def menu_paths
    Rails.application.routes.routes.filter_map do |r|
      path = r.path.spec.to_s.delete_suffix("(.:format)")
      path if r.verb == "GET" && path.start_with?("/dashboard") && path.exclude?(":") && %w[/dashboard/security/recovery_codes /dashboard/products/export].exclude?(path)
    end.uniq
  end

  test "データがない契約でも、すべての一覧・登録画面が共通の枠と見出しで表示される" do
    sign_in @user
    menu_paths.each do |path|
      get path
      follow_redirect! while response.redirect?
      assert_response :success, path
      assert_select "html[lang=ja]", 1, path
      assert_select "h1", { count: 1 }, path
      assert_select "nav.side-nav", { count: 1 }, path
      assert_select "footer.main-footer", { count: 1 }, path
      assert_select "nav.bottom-nav", { count: 1 }, path
      assert_no_match(/translation missing/i, response.body, path)
    end
  end

  test "メニューのリンク先はすべて開ける" do
    sign_in @user
    get dashboard_root_path
    links = css_select("nav.side-nav a").map { |a| a["href"] }
    assert_operator links.size, :>=, 35
    assert_equal links.uniq, links
    links.each do |href|
      get href
      assert_response :success, href
      assert_select "nav.side-nav [aria-current=page]", { minimum: href == dashboard_help_path ? 0 : 1 }, href
    end
  end

  test "閲覧のみのメンバーには登録ボタンと権限のないメニューを表示しない" do
    sign_in member("viewer")
    get dashboard_products_path
    assert_select "a[href=?]", new_dashboard_product_path, 0
    assert_select ".readonly-note"
    assert_select "nav.side-nav a[href=?]", dashboard_members_path, 0
    assert_select "nav.side-nav a[href=?]", dashboard_account_settings_path, 0
  end

  test "ホームに準備の手順と今日の売上を表示し、準備が終わると手順を消す" do
    sign_in @user
    get dashboard_root_path
    assert_select ".setup-steps li", 5
    assert_select ".setup-steps li.next", 1

    store = @user.stores.create!(name: "S1", ascii_name: "storeui")
    @user.products.create!(code: "P", name: "商品", price: 100, tax_rate: 10)
    @user.employees.create!(code: "1", name: "担当", pin: "1234")
    pos = store.pos_tokens.create!(name: "P1", ascii_name: "posui", password: "x", password_confirmation: "x")
    pos.update_columns(last_used_at: Time.current)
    employee = @user.employees.first
    Sale.create!(user: @user, store: store, pos_token: pos, employee: employee, total_amount: 12_340, payment_method: :cash, business_date: Date.current)

    get dashboard_root_path
    assert_select ".setup-steps", 0
    assert_select ".kpi-value", text: /¥12,340/
  end

  test "検索条件なしで開いた一覧は、最近の売上をすぐに表示する" do
    store = @user.stores.create!(name: "S1", ascii_name: "storeui")
    recent = Sale.create!(user: @user, store: store, total_amount: 1_000, payment_method: :cash)
    sign_in @user
    get dashboard_sales_path
    assert_match recent.receipt_number, response.body
    assert_select "td", text: "現金"
    assert_select "td", text: "¥1,000"
  end

  test "在庫は商品名で探せて、ほかの契約の在庫は表示しない" do
    other = User.create!(login_name: "uiother", email: "other@example.com", password: "Password1!", password_confirmation: "Password1!",
                         first_name: "a", last_name: "b", user_type: :individual, confirmed_at: Time.current)
    [ [ @user, "自社おにぎり", "uistore1" ], [ other, "他社おにぎり", "uistore2" ] ].each do |u, name, ascii|
      store = u.stores.create!(name: name, ascii_name: ascii)
      StoreStock.create!(store: store, product: u.products.create!(code: "X", name: name, price: 1, tax_rate: 8), quantity: 3)
    end
    sign_in @user
    get dashboard_store_stocks_path(q: "おにぎり")
    assert_match "自社おにぎり", response.body
    assert_no_match "他社おにぎり", response.body
    get dashboard_store_stocks_path(store_id: other.stores.first.id)
    assert_no_match "他社おにぎり", response.body
  end

  test "ログイン後は管理画面のホームへ移動する" do
    post user_session_path, params: { user: { email: @user.email, password: "Password1!" } }
    @user.update!(otp_enabled_at: Time.current, otp_secret_ciphertext: User.otp_secret_encryptor.encrypt_and_sign(ROTP::Base32.random))
    sign_in @user
    get new_user_session_path
    assert_redirected_to dashboard_root_path
  end
end
