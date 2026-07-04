require "test_helper"

class JournalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "journaltest",
      email: "journaltest@example.com",
      password: "Password1!", password_confirmation: "Password1!",
      first_name: "電子", last_name: "ジャーナル",
      user_type: :individual, confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "ジャーナル店", ascii_name: "journalst")
    @pos = @store.pos_tokens.create!(
      name: "POS1", ascii_name: "pos1",
      password: "PosPass1!", password_confirmation: "PosPass1!"
    )
    @pos.update_columns(token: SecureRandom.hex(32))

    @emp = @user.employees.create!(code: "J001", name: "担当者A", pin: "1234")
    @emp.stores << @store
    @emp.employee_permissions.create!(permission: "view_journal")

    @emp_no_perm = @user.employees.create!(code: "J002", name: "担当者B", pin: "5678")
    @emp_no_perm.stores << @store

    @auth = { "Authorization" => "Bearer #{@pos.token}" }
  end

  # ── JournalEntry 作成 ───────────────────────────────────────────────────────

  test "Sale 作成で JournalEntry が1件作られる" do
    product = @user.products.create!(code: "P001", name: "商品A", price: 500, tax_rate: 10)

    assert_difference "JournalEntry.count", 1 do
      post "/api/v1/sales",
           params: {
             sale: { total_amount: 550, payment_method: 0, subtotal_ex_tax: 500, tax_amount: 50 },
             details: [ { product_id: product.id, product_name: "商品A", quantity: 1,
                          unit_price: 550, subtotal: 550, tax_rate: 10, tax_amount: 50 } ],
             payments: [ { method: 0, amount: 550 } ],
             employee_id: @emp.id
           },
           headers: @auth, as: :json
    end

    assert_response :created
    entry = JournalEntry.last
    assert_equal "sale", entry.entry_type
    assert_equal @store.id, entry.store_id
    assert_equal @pos.id, entry.pos_token_id
    assert_not_nil entry.receipt_number
    assert_equal 550, entry.payload["total_amount"]
    assert_equal 1, entry.payload["details"].length
  end

  test "Refund 作成で JournalEntry が1件作られる" do
    product = @user.products.create!(code: "P002", name: "商品B", price: 1000, tax_rate: 10)

    # 先に売上を作成
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 1100, payment_method: 0, subtotal_ex_tax: 1000, tax_amount: 100 },
           details: [ { product_id: product.id, product_name: "商品B", quantity: 1,
                        unit_price: 1100, subtotal: 1100, tax_rate: 10, tax_amount: 100 } ],
           payments: [ { method: 0, amount: 1100 } ],
           employee_id: @emp.id
         },
         headers: @auth, as: :json
    sale_data = JSON.parse(response.body)
    receipt_number = sale_data["receipt_number"]
    sale = Sale.find_by(receipt_number: receipt_number)
    saledetail = sale.saledetails.first

    emp2 = @user.employees.create!(code: "J003", name: "承認者", pin: "9999")
    emp2.stores << @store
    emp2.employee_permissions.create!(permission: "refund")
    @emp.employee_permissions.create!(permission: "refund")

    assert_difference "JournalEntry.count", 1 do
      post "/api/v1/refunds",
           params: {
             receipt_number: receipt_number,
             employee_ids: [ @emp.id, emp2.id ],
             details: [ { saledetail_id: saledetail.id, quantity: 1 } ]
           },
           headers: @auth, as: :json
    end

    assert_response :created
    entry = JournalEntry.where(entry_type: :refund).last
    assert_not_nil entry
    assert_equal @store.id, entry.store_id
    assert_not_nil entry.payload["refund_receipt_number"]
    assert_not_nil entry.payload["original_receipt_number"]
  end

  test "レジ開設で JournalEntry(register_open) が1件作られる" do
    assert_difference "JournalEntry.count", 1 do
      post "/api/v1/pos_devices/open",
           params: {
             employee_id: @emp.id,
             open_date: Date.current.to_s,
             cash_drawer: { "10000": 1, "5000": 0, "1000": 0, "500": 0,
                            "100": 0, "50": 0, "10": 0, "5": 0, "1": 0 },
             total_amount: 10_000
           },
           headers: @auth, as: :json
    end

    assert_response :ok
    entry = JournalEntry.last
    assert_equal "register_open", entry.entry_type
    assert_equal 10_000, entry.payload["total_amount"]
  end

  test "レジ金チェックで JournalEntry(cash_check) が1件作られる" do
    assert_difference "JournalEntry.count", 1 do
      post "/api/v1/pos_devices/cash_check",
           params: {
             employee_id: @emp.id,
             cash_drawer: { "10000": 2, "5000": 0, "1000": 0, "500": 0,
                            "100": 0, "50": 0, "10": 0, "5": 0, "1": 0 },
             total_amount: 20_000
           },
           headers: @auth, as: :json
    end

    assert_response :ok
    entry = JournalEntry.last
    assert_equal "cash_check", entry.entry_type
    assert_equal 20_000, entry.payload["total_amount"]
  end

  test "途中回収で JournalEntry(cash_pickup) が1件作られる" do
    @emp.employee_permissions.create!(permission: "cash_pickup")

    assert_difference "JournalEntry.count", 1 do
      post "/api/v1/pos_devices/cash_pickup",
           params: { employee_id: @emp.id, amount: 5_000, reason: "金庫へ" },
           headers: @auth, as: :json
    end

    assert_response :ok
    entry = JournalEntry.last
    assert_equal "cash_pickup", entry.entry_type
    assert_equal 5_000, entry.payload["pickup_amount"]
    assert_equal "金庫へ",   entry.payload["pickup_reason"]
  end

  test "レジ精算で JournalEntry(register_close) が1件作られる" do
    assert_difference "JournalEntry.count", 1 do
      post "/api/v1/pos_devices/close_register",
           params: {
             employee_id: @emp.id,
             cash_drawer: { "10000": 1, "5000": 0, "1000": 0, "500": 0,
                            "100": 0, "50": 0, "10": 0, "5": 0, "1": 0 },
             total_amount: 10_000
           },
           headers: @auth, as: :json
    end

    assert_response :ok
    entry = JournalEntry.last
    assert_equal "register_close", entry.entry_type
  end

  # ── GET /api/v1/journals（一覧）─────────────────────────────────────────────

  test "view_journal 権限がない場合は 403" do
    get "/api/v1/journals",
        params: { employee_id: @emp_no_perm.id },
        headers: @auth, as: :json

    assert_response :forbidden
    data = JSON.parse(response.body)
    assert_equal false, data["success"]
  end

  test "view_journal 権限ありで一覧が返る" do
    JournalEntry.create!(
      user: @user, store: @store, pos_token: @pos, employee: @emp,
      entry_type: :sale, receipt_number: "R001",
      printed_at: Time.current, payload: { total_amount: 1000 }
    )

    get "/api/v1/journals",
        params: { employee_id: @emp.id },
        headers: @auth, as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    assert data["success"]
    assert data["entries"].is_a?(Array)
    assert data["entries"].any? { |e| e["receipt_number"] == "R001" }
  end

  test "日付フィルタが機能する" do
    JournalEntry.create!(
      user: @user, store: @store, pos_token: @pos,
      entry_type: :sale, receipt_number: "TODAY",
      printed_at: Date.current.beginning_of_day + 1.hour,
      payload: { total_amount: 500 }
    )
    JournalEntry.create!(
      user: @user, store: @store, pos_token: @pos,
      entry_type: :sale, receipt_number: "YESTERDAY",
      printed_at: Date.yesterday.beginning_of_day + 1.hour,
      payload: { total_amount: 300 }
    )

    get "/api/v1/journals",
        params: { employee_id: @emp.id, date: Date.current.to_s },
        headers: @auth, as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    receipts = data["entries"].map { |e| e["receipt_number"] }
    assert_includes receipts, "TODAY"
    assert_not_includes receipts, "YESTERDAY"
  end

  test "entry_type フィルタが機能する" do
    JournalEntry.create!(
      user: @user, store: @store, pos_token: @pos,
      entry_type: :sale, receipt_number: "S001",
      printed_at: Time.current, payload: { total_amount: 500 }
    )
    JournalEntry.create!(
      user: @user, store: @store, pos_token: @pos,
      entry_type: :register_open,
      printed_at: Time.current, payload: { total_amount: 10_000 }
    )

    get "/api/v1/journals",
        params: { employee_id: @emp.id, type: "sale" },
        headers: @auth, as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    assert data["entries"].all? { |e| e["entry_type"] == "sale" }
  end

  test "他店舗のジャーナルは見えない" do
    other_user  = User.create!(
      login_name: "otherjrnl", email: "otherjrnl@example.com",
      password: "Password1!", password_confirmation: "Password1!",
      first_name: "他", last_name: "店", user_type: :individual,
      confirmed_at: Time.current
    )
    other_store = other_user.stores.create!(name: "他店", ascii_name: "other2st")
    other_pos   = other_store.pos_tokens.create!(
      name: "OPOS", ascii_name: "opos1",
      password: "PosPass1!", password_confirmation: "PosPass1!"
    )
    JournalEntry.create!(
      user: other_user, store: other_store, pos_token: other_pos,
      entry_type: :sale, receipt_number: "OTHER-001",
      printed_at: Time.current, payload: { total_amount: 999 }
    )

    get "/api/v1/journals",
        params: { employee_id: @emp.id },
        headers: @auth, as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    assert data["entries"].none? { |e| e["receipt_number"] == "OTHER-001" }
  end

  # ── GET /api/v1/journals/:id（詳細）────────────────────────────────────────

  test "詳細取得で payload が含まれる" do
    entry = JournalEntry.create!(
      user: @user, store: @store, pos_token: @pos,
      entry_type: :sale, receipt_number: "DETAIL001",
      printed_at: Time.current, payload: { total_amount: 1234, details: [] }
    )

    get "/api/v1/journals/#{entry.id}",
        params: { employee_id: @emp.id },
        headers: @auth, as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    assert data["success"]
    assert_equal "DETAIL001", data["entry"]["receipt_number"]
    assert_not_nil data["entry"]["payload"]
    assert_equal 1234, data["entry"]["payload"]["total_amount"]
  end

  test "他店舗の JournalEntry ID を指定すると 404" do
    other_user  = User.create!(
      login_name: "otherjrnl2", email: "otherjrnl2@example.com",
      password: "Password1!", password_confirmation: "Password1!",
      first_name: "他2", last_name: "店", user_type: :individual,
      confirmed_at: Time.current
    )
    other_store = other_user.stores.create!(name: "他店2", ascii_name: "other3st")
    other_pos   = other_store.pos_tokens.create!(
      name: "OPOS2", ascii_name: "opos2",
      password: "PosPass1!", password_confirmation: "PosPass1!"
    )
    other_entry = JournalEntry.create!(
      user: other_user, store: other_store, pos_token: other_pos,
      entry_type: :sale, receipt_number: "OTHER-002",
      printed_at: Time.current, payload: { total_amount: 100 }
    )

    get "/api/v1/journals/#{other_entry.id}",
        params: { employee_id: @emp.id },
        headers: @auth, as: :json

    assert_response :not_found
  end
end
