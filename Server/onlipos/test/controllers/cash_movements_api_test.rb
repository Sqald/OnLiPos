require "test_helper"

# レジ入出金 API のテスト。
# 入金（釣銭補充・雑入金）と出金（途中回収・雑出金）が理論在高に反映されることを確認する。
class CashMovementsApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "cashmvtest",
      email: "cashmvtest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "入出金テスト店舗", ascii_name: "cashmvstore")
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @pos_token.update_columns(token: SecureRandom.hex(32))
    @auth = { "Authorization" => "Bearer #{@pos_token.token}" }

    @employee = @user.employees.create!(code: "E001", name: "田中一郎")
    @employee.stores << @store
    @employee.employee_permissions.create!(permission: "cash_pickup")
    @employee.employee_permissions.create!(permission: "open_register")

    @no_perm_employee = @user.employees.create!(code: "E002", name: "権限なし")
    @no_perm_employee.stores << @store

    # レジ開設（釣銭準備金 30,000 円）
    post "/api/v1/pos_devices/open",
         params: {
           employee_id: @employee.id, open_date: Date.current.to_s,
           cash_drawer: { "10000": 3, "5000": 0, "1000": 0, "500": 0, "100": 0, "50": 0, "10": 0, "5": 0, "1": 0 }
         },
         headers: @auth, as: :json
    @session = RegisterSession.open.find_by(pos_token: @pos_token)
  end

  def post_movement(kind:, amount:, employee_id: nil, reason: nil)
    post "/api/v1/cash_movements",
         params: { employee_id: employee_id || @employee.id, kind: kind, amount: amount, reason: reason },
         headers: @auth, as: :json
  end

  test "釣銭補充（入金）が理論在高に加算される" do
    post_movement(kind: "replenishment", amount: 5000, reason: "釣銭補充")
    assert_response :created
    data = JSON.parse(response.body)
    assert_equal "inbound", data["direction"]

    movement = CashMovement.find(data["movement_id"])
    assert_equal @session.id, movement.register_session_id

    get "/api/v1/pos_devices/cash_check_context", headers: @auth, as: :json
    assert_equal 35_000, JSON.parse(response.body)["expected_amount"]
  end

  test "雑出金が理論在高から減算される" do
    post_movement(kind: "misc_out", amount: 2000, reason: "備品購入")
    assert_response :created

    get "/api/v1/pos_devices/cash_check_context", headers: @auth, as: :json
    assert_equal 28_000, JSON.parse(response.body)["expected_amount"]
  end

  test "数値コードでも種別を指定できる（途中回収=0）" do
    post_movement(kind: 0, amount: 10_000)
    assert_response :created
    data = JSON.parse(response.body)
    assert_equal "pickup", data["kind"]
    assert_equal "outbound", data["direction"]

    get "/api/v1/pos_devices/cash_check_context", headers: @auth, as: :json
    assert_equal 20_000, JSON.parse(response.body)["expected_amount"]
  end

  test "入出金でジャーナルが記録される" do
    assert_difference -> { JournalEntry.cash_movement.count }, 1 do
      post_movement(kind: "misc_in", amount: 1000, reason: "レジ精算差額訂正")
    end
    entry = JournalEntry.cash_movement.last
    assert_equal 1000, entry.payload["amount"]
    assert_equal "misc_in", entry.payload["kind"]
    assert_equal @session.z_number, entry.payload["z_number"]
  end

  test "権限なし従業員は403" do
    post_movement(kind: "replenishment", amount: 1000, employee_id: @no_perm_employee.id)
    assert_response :forbidden
  end

  test "不正な種別・金額は422" do
    post_movement(kind: "unknown", amount: 1000)
    assert_response :unprocessable_entity

    post_movement(kind: "replenishment", amount: 0)
    assert_response :unprocessable_entity
  end

  test "精算スナップショットに入出金合計が保存される" do
    post_movement(kind: "replenishment", amount: 5000)
    post_movement(kind: "misc_out", amount: 2000)

    post "/api/v1/pos_devices/close_register",
         params: {
           employee_id: @employee.id,
           cash_drawer: { "10000": 3, "5000": 0, "1000": 3, "500": 0, "100": 0, "50": 0, "10": 0, "5": 0, "1": 0 }
         },
         headers: @auth, as: :json
    assert_response :ok

    @session.reload
    assert_equal 5000, @session.cash_in_total
    assert_equal 2000, @session.cash_out_total
    # 期待在高 30000 + 5000 - 2000 = 33000 / 実査 33000 → 過不足 0
    assert_equal 33_000, @session.expected_cash_amount
    assert_equal 0, @session.cash_diff_amount
  end

  test "一覧が現在セッションの入出金を返す" do
    post_movement(kind: "replenishment", amount: 5000)
    post_movement(kind: "misc_out", amount: 2000)

    get "/api/v1/cash_movements", headers: @auth, as: :json
    assert_response :ok
    data = JSON.parse(response.body)
    assert_equal 2, data["movements"].size
  end
end
