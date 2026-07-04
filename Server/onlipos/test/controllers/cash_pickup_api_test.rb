require "test_helper"

# 途中回収（cash_pickup）の APIテスト
class CashPickupApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "pickuptest",
      email: "pickuptest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "途中",
      last_name: "回収",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "回収テスト店", ascii_name: "pickupstore")
    @pos = @store.pos_tokens.create!(
      name: "POS1", ascii_name: "pos1",
      password: "PosPass1!", password_confirmation: "PosPass1!"
    )
    @pos.update_columns(token: SecureRandom.hex(32))

    # 途中回収権限なし従業員
    @emp_no_perm = @user.employees.create!(code: "E001", name: "権限なし", pin: "1111")
    @emp_no_perm.stores << @store

    # 途中回収権限あり従業員
    @emp_with_perm = @user.employees.create!(code: "E002", name: "回収担当", pin: "2222")
    @emp_with_perm.stores << @store
    @emp_with_perm.employee_permissions.create!(permission: "cash_pickup")

    @auth_header = { "Authorization" => "Bearer #{@pos.token}" }
  end

  # ── 権限チェック ────────────────────────────────────────────────

  test "cash_pickup 権限なしの従業員は 403 になる" do
    post "/api/v1/pos_devices/cash_pickup",
         params: { employee_id: @emp_no_perm.id, amount: 5000 },
         headers: @auth_header,
         as: :json

    assert_response :forbidden
    data = JSON.parse(response.body)
    assert_equal false, data["success"]
  end

  test "cash_pickup 権限あり従業員は回収に成功する" do
    post "/api/v1/pos_devices/cash_pickup",
         params: { employee_id: @emp_with_perm.id, amount: 5000, reason: "金庫に移動" },
         headers: @auth_header,
         as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    assert data["success"]
    assert_equal 5000, data["pickup_amount"]
    assert_not_nil data["pickup_id"]

    log = CashLog.find(data["pickup_id"])
    assert log.is_pickup
    assert_equal 5000, log.pickup_amount
    assert_equal "金庫に移動", log.pickup_reason
  end

  test "amount が 0 以下のとき 422 になる" do
    post "/api/v1/pos_devices/cash_pickup",
         params: { employee_id: @emp_with_perm.id, amount: 0 },
         headers: @auth_header,
         as: :json

    assert_response :unprocessable_entity
    data = JSON.parse(response.body)
    assert_equal false, data["success"]
  end

  test "他店舗の従業員 ID を渡すと 403 になる" do
    other_user  = User.create!(
      login_name: "otherpu", email: "otherpu@example.com",
      password: "Password1!", password_confirmation: "Password1!",
      first_name: "他", last_name: "社員", user_type: :individual,
      confirmed_at: Time.current
    )
    other_store = other_user.stores.create!(name: "他店", ascii_name: "otherst")
    other_emp   = other_user.employees.create!(code: "O001", name: "他担当", pin: "9999")
    other_emp.stores << other_store
    other_emp.employee_permissions.create!(permission: "cash_pickup")

    post "/api/v1/pos_devices/cash_pickup",
         params: { employee_id: other_emp.id, amount: 3000 },
         headers: @auth_header,
         as: :json

    assert_response :forbidden
  end

  # ── expected_amount への反映 ─────────────────────────────────────

  test "途中回収後に cash_check_context の expected_amount が回収額だけ減る" do
    # レジ開設ログ（開始額 50000円）
    opening_log = CashLog.create!(
      pos_token: @pos, employee: @emp_with_perm,
      open_date: Date.current, is_start: true, is_end: false,
      yen_10000: 5, yen_5000: 0, yen_1000: 0, yen_500: 0, yen_100: 0,
      yen_50: 0, yen_10: 0, yen_5: 0, yen_1: 0
    )

    # 途中回収ログ（10000円回収）
    CashLog.create!(
      pos_token: @pos, employee: @emp_with_perm,
      open_date: Date.current, is_start: false, is_end: false,
      is_pickup: true, pickup_amount: 10_000, pickup_reason: "両替",
      yen_10000: 0, yen_5000: 0, yen_1000: 0, yen_500: 0, yen_100: 0,
      yen_50: 0, yen_10: 0, yen_5: 0, yen_1: 0
    )

    get "/api/v1/pos_devices/cash_check_context",
        headers: @auth_header,
        as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    assert data["success"]
    # 売上・返金なし → expected = 50000 - 10000 = 40000
    assert_equal 40_000, data["expected_amount"]
  end

  test "途中回収が複数ある場合は合計分だけ expected_amount が減る" do
    CashLog.create!(
      pos_token: @pos, employee: @emp_with_perm,
      open_date: Date.current, is_start: true, is_end: false,
      yen_10000: 3, yen_5000: 0, yen_1000: 0, yen_500: 0, yen_100: 0,
      yen_50: 0, yen_10: 0, yen_5: 0, yen_1: 0
    )
    CashLog.create!(
      pos_token: @pos, employee: @emp_with_perm,
      open_date: Date.current, is_start: false, is_end: false,
      is_pickup: true, pickup_amount: 5_000,
      yen_10000: 0, yen_5000: 0, yen_1000: 0, yen_500: 0, yen_100: 0,
      yen_50: 0, yen_10: 0, yen_5: 0, yen_1: 0
    )
    CashLog.create!(
      pos_token: @pos, employee: @emp_with_perm,
      open_date: Date.current, is_start: false, is_end: false,
      is_pickup: true, pickup_amount: 8_000,
      yen_10000: 0, yen_5000: 0, yen_1000: 0, yen_500: 0, yen_100: 0,
      yen_50: 0, yen_10: 0, yen_5: 0, yen_1: 0
    )

    get "/api/v1/pos_devices/cash_check_context",
        headers: @auth_header,
        as: :json

    assert_response :ok
    data = JSON.parse(response.body)
    # 開始額 30000 - (5000 + 8000) = 17000
    assert_equal 17_000, data["expected_amount"]
  end
end
