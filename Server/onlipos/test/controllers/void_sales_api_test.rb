require "test_helper"

# 確定後取消（VOID）API のテスト。
# 二重承認・在庫戻し・ジャーナル記録・現金理論在高からの除外・締め後の取消禁止を確認する。
class VoidSalesApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "voidtest",
      email: "voidtest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "取消テスト店舗", ascii_name: "voidstore")
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @pos_token.update_columns(token: SecureRandom.hex(32))
    @auth = { "Authorization" => "Bearer #{@pos_token.token}" }

    @employee = @user.employees.create!(code: "E001", name: "田中一郎")
    @employee2 = @user.employees.create!(code: "E002", name: "佐藤二郎")
    [ @employee, @employee2 ].each do |e|
      e.stores << @store
      e.employee_permissions.create!(permission: "refund")
    end
    @no_perm = @user.employees.create!(code: "E003", name: "権限なし")
    @no_perm.stores << @store

    @product = @user.products.create!(code: "P001", name: "商品A", price: 1100, tax_rate: 10)
    @stock = StoreStock.create!(store: @store, product: @product, quantity: 100)

    # レジ開設（30,000円）
    post "/api/v1/pos_devices/open",
         params: {
           employee_id: @employee.id, open_date: Date.current.to_s,
           cash_drawer: { "10000": 3, "5000": 0, "1000": 0, "500": 0, "100": 0, "50": 0, "10": 0, "5": 0, "1": 0 }
         },
         headers: @auth, as: :json

    # 現金売上 1100（在庫 100 → 99）
    post "/api/v1/sales",
         params: {
           sale: { total_amount: 1100, subtotal_ex_tax: 0, tax_amount: 0 },
           employee_id: @employee.id,
           details: [ { product_id: @product.id, quantity: 1, unit_price: 1100, subtotal: 1100, tax_rate: 10 } ],
           payments: [ { method: 0, amount: 1100 } ]
         },
         headers: @auth, as: :json
    @sale = Sale.find(JSON.parse(response.body)["sale_id"])
  end

  def post_void(sale: @sale, employee_ids: nil, reason: "打ち間違い")
    post "/api/v1/sales/#{sale.id}/void",
         params: {
           employee_ids: employee_ids || [ @employee.id, @employee2.id ],
           reason: reason
         },
         headers: @auth, as: :json
  end

  test "取消で状態遷移・在庫戻し・ジャーナル記録・理論在高の除外が行われる" do
    assert_equal 99, @stock.reload.quantity

    assert_difference -> { JournalEntry.void.count }, 1 do
      post_void
    end
    assert_response :ok

    @sale.reload
    assert @sale.voided?
    assert_equal "打ち間違い", @sale.void_reason
    assert_equal @employee.id, @sale.voided_by_employee_id
    assert_not_nil @sale.voided_at

    # 在庫が戻る
    assert_equal 100, @stock.reload.quantity
    assert StockMovement.exists?(sale: @sale, reason: "void")

    # 現金理論在高から除外される（30000 + 0）
    get "/api/v1/pos_devices/cash_check_context", headers: @auth, as: :json
    assert_equal 30_000, JSON.parse(response.body)["expected_amount"]

    # ジャーナルに取消理由と承認者
    entry = JournalEntry.void.last
    assert_equal "打ち間違い", entry.payload["void_reason"]
    assert_equal [ "田中一郎", "佐藤二郎" ], entry.payload["approver_names"]
  end

  test "取消済みの会計は再取消できない" do
    post_void
    assert_response :ok

    post_void
    assert_response :unprocessable_entity
    # 在庫は1回分だけ戻っている
    assert_equal 100, @stock.reload.quantity
  end

  test "返品済みの会計は取消できない" do
    post "/api/v1/refunds",
         params: {
           receipt_number: @sale.receipt_number,
           employee_ids: [ @employee.id, @employee2.id ],
           details: [ { saledetail_id: @sale.saledetails.first.id, quantity: 1 } ]
         },
         headers: @auth, as: :json
    assert_response :created

    post_void
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["message"], "返品処理済み"
  end

  test "精算済みセッションの売上は取消できない" do
    post "/api/v1/pos_devices/close_register",
         params: {
           employee_id: @employee.id,
           cash_drawer: { "10000": 3, "5000": 0, "1000": 1, "500": 1, "100": 6, "50": 0, "10": 0, "5": 0, "1": 0 }
         },
         headers: @auth, as: :json
    assert_response :ok

    post_void
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["message"], "精算済み"
  end

  test "承認者が1名では取消できない" do
    post_void(employee_ids: [ @employee.id ])
    assert_response :forbidden
  end

  test "権限のない従業員を含む承認では取消できない" do
    post_void(employee_ids: [ @employee.id, @no_perm.id ])
    assert_response :forbidden
  end

  test "取消理由は必須" do
    post_void(reason: "")
    assert_response :bad_request
  end

  test "精算スナップショットに取消件数・金額が記録される" do
    post_void
    assert_response :ok

    post "/api/v1/pos_devices/close_register",
         params: {
           employee_id: @employee.id,
           cash_drawer: { "10000": 3, "5000": 0, "1000": 0, "500": 0, "100": 0, "50": 0, "10": 0, "5": 0, "1": 0 }
         },
         headers: @auth, as: :json
    assert_response :ok

    session = RegisterSession.find_by(pos_token: @pos_token)
    assert_equal 1, session.void_count
    assert_equal 1100, session.void_total
    assert_equal 0, session.sales_count
    assert_equal 30_000, session.expected_cash_amount
    assert_equal 0, session.cash_diff_amount
  end
end
