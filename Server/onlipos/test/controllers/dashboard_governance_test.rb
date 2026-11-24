require "test_helper"

# メンバーの役割・操作履歴・再認証・端末停止・精算/ジャーナル画面
class DashboardGovernanceTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  BROWSER = { "User-Agent" => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/140.0.0.0 Safari/537.36" }.freeze

  setup do
    @owner = build_user("ownerone")
    @store = @owner.stores.create!(name: "S1", ascii_name: "storeone")
    @pos = @store.pos_tokens.create!(name: "P1", ascii_name: "pos1", password: "x", password_confirmation: "x")
    @product = @owner.products.create!(code: "A", name: "A", price: 100)
    sign_in @owner
  end

  def build_user(name, **attrs)
    User.create!({ login_name: name, email: "#{name}@example.com", password: "Password1!", password_confirmation: "Password1!",
                   first_name: "a", last_name: "b", user_type: :individual, confirmed_at: Time.current }.merge(attrs))
  end

  def member(role) = build_user("member#{role}", owner: @owner, role: role)

  def reauthenticate = post(dashboard_reauthentication_path, params: { password: "Password1!" })

  test "全画面が表示できる" do
    emp = @owner.employees.create!(code: "E", name: "E")
    session = @pos.register_sessions.create!(user: @owner, store: @store, business_date: Date.current, z_number: 1, opened_at: Time.current)
    log = CashLog.create!(pos_token: @pos, employee: emp, open_date: Date.current, is_start: true, log_type: :open, register_session: session,
                          yen_10000: 1, yen_5000: 0, yen_1000: 0, yen_500: 0, yen_100: 0, yen_50: 0, yen_10: 0, yen_5: 0, yen_1: 0)
    entry = JournalEntry.create_from_cash_log!(log, :register_open)
    sale = Sale.create!(user: @owner, store: @store, pos_token: @pos, total_amount: 100, review_reasons: [ "理由" ])
    reauthenticate
    [ dashboard_root_path, dashboard_account_settings_path, dashboard_members_path, new_dashboard_member_path, dashboard_audit_logs_path,
      dashboard_sale_reviews_path, dashboard_register_sessions_path, dashboard_register_session_path(session), dashboard_journals_path,
      dashboard_journal_path(entry), verify_dashboard_journals_path, dashboard_security_path, new_dashboard_reauthentication_path,
      dashboard_register_sessions_path(format: :csv), dashboard_journals_path(format: :csv), dashboard_products_path, dashboard_stores_path,
      dashboard_employees_path, dashboard_sale_detail_path(sale) ].each do |path|
      get path, headers: BROWSER
      assert_response :ok, path
    end

    patch dashboard_sale_review_path(sale)
    assert_not_nil sale.reload.reviewed_at
  end

  test "閲覧のみのメンバーは変更できず、契約者のデータだけが見える" do
    other = build_user("otherone")
    other.products.create!(code: "X", name: "他社商品", price: 1)
    sign_in member(:viewer)
    get dashboard_products_path, headers: BROWSER
    assert_response :ok
    assert_match "A", response.body
    assert_no_match "他社商品", response.body

    patch dashboard_product_path(@product), params: { product: { price: 1 } }
    assert_redirected_to dashboard_root_path
    assert_equal 100, @product.reload.price
    get dashboard_members_path, headers: BROWSER
    assert_redirected_to dashboard_root_path
  end

  test "管理者メンバーは商品を変更でき、契約・メンバー・操作履歴は扱えない" do
    sign_in member(:manager)
    patch dashboard_product_path(@product), params: { product: { price: 200 } }
    assert_equal 200, @product.reload.price
    log = @owner.audit_logs.where(target_type: "Product", action: "update").last
    assert_equal [ 100, 200 ], log.details["price"]
    assert_equal "User", log.actor_type

    patch dashboard_account_settings_path, params: { user: { invoice_registration_number: "T1234567890123" } }
    assert_nil @owner.reload.invoice_registration_number
    get dashboard_audit_logs_path, headers: BROWSER
    assert_redirected_to dashboard_root_path
  end

  test "契約者はメンバーを追加でき、パスワード再入力が必要" do
    params = { user: { login_name: "newmember", email: "new@example.com", last_name: "新", first_name: "人", role: "owner", owner_id: 1 } }
    post dashboard_members_path, params: params
    assert_redirected_to new_dashboard_reauthentication_path
    reauthenticate
    post dashboard_members_path, params: params
    created = User.find_by!(login_name: "newmember")
    assert_equal @owner, created.account
    assert created.role_viewer?, "契約者の役割は付与できない"
  end

  test "インボイス登録番号と端数処理を設定できる" do
    patch dashboard_account_settings_path, params: { user: { invoice_registration_number: "T1234567890123", tax_rounding_method: "round_half_up" } }
    assert_equal "T1234567890123", @owner.reload.invoice_registration_number
    patch dashboard_account_settings_path, params: { user: { invoice_registration_number: "X" } }
    assert_response :unprocessable_entity
  end

  test "MFAの変更にはパスワードの再入力が必要" do
    post dashboard_security_recovery_codes_path
    assert_redirected_to new_dashboard_reauthentication_path
    post dashboard_reauthentication_path, params: { password: "wrong" }
    assert_response :unprocessable_entity
    reauthenticate
    post dashboard_security_recovery_codes_path
    assert_redirected_to dashboard_security_recovery_codes_path
  end

  test "すべての端末からログアウトできる" do
    reauthenticate
    post dashboard_security_sign_out_everywhere_path
    assert_equal 1, @owner.reload.session_version
  end

  test "端末を停止するとAPIを使えなくなり、解除すると戻る" do
    headers = { "Authorization" => "Bearer #{@pos.token}" }
    patch disable_dashboard_pos_device_path(@pos)
    get "/api/v1/store_stocks", headers: headers
    assert_response :unauthorized
    patch enable_dashboard_pos_device_path(@pos)
    get "/api/v1/store_stocks", headers: headers
    assert_response :ok
  end

  test "端末トークンは平文で保存されず、URLパラメータでは認証できない" do
    assert_not_includes PosToken.column_names, "token"
    get "/api/v1/store_stocks?Token=#{@pos.token}"
    assert_response :unauthorized
  end

  test "MIN_APP_VERSION より古いアプリは拒否する" do
    ENV["MIN_APP_VERSION"] = "1.2.0"
    headers = { "Authorization" => "Bearer #{@pos.token}" }
    get "/api/v1/store_stocks", headers: headers.merge("X-App-Version" => "1.1.9")
    assert_response :upgrade_required
    get "/api/v1/store_stocks", headers: headers.merge("X-App-Version" => "1.2.0")
    assert_response :ok
  ensure
    ENV.delete("MIN_APP_VERSION")
  end

  test "ジャーナルはSQLでも更新・削除できず、末尾の削除は検知される" do
    emp = @owner.employees.create!(code: "E", name: "E")
    movements = Array.new(2) do
      CashMovement.create!(store: @store, pos_token: @pos, employee: emp, kind: :replenishment, direction: :inbound, amount: 100, occurred_at: Time.current)
    end
    entries = movements.map { |m| JournalEntry.create_from_cash_movement!(m) }
    assert_empty JournalEntry.verify_chain(@pos)
    assert_raises(ActiveRecord::StatementInvalid) { JournalEntry.transaction(requires_new: true) { JournalEntry.where(id: entries.last.id).delete_all } }
    assert_raises(ActiveRecord::StatementInvalid) { JournalEntry.transaction(requires_new: true) { JournalEntry.update_all(receipt_number: "x") } }

    JournalVerificationJob.perform_now
    assert_equal 2, JournalAnchor.last.sequence_number
    JournalProtection.allow { JournalEntry.where(id: entries.last.id).delete_all }
    assert_match "末尾の欠落", JournalEntry.verify_chain(@pos).first
    @pos.update_columns(next_journal_sequence: 2)
    assert_match "控えとの不一致", JournalEntry.verify_chain(@pos).first
  end

  test "退会にはパスワードが必要で、取引記録があれば削除されない" do
    delete user_registration_path
    assert User.exists?(@owner.id)
    Sale.create!(user: @owner, store: @store, pos_token: @pos, total_amount: 100)
    delete user_registration_path, params: { current_password: "Password1!" }
    assert User.exists?(@owner.id)
    assert_equal 1, Sale.count
  end

  test "CSVの数式は無害化される" do
    assert_equal "'=1+1", CsvExport.cell("=1+1")
    assert_equal(-5, CsvExport.cell(-5))
  end
end
