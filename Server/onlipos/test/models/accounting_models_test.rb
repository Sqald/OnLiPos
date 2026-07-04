require "test_helper"

# フェーズ3で新設した会計モデル（RegisterSession / SaleTaxBreakdown /
# RefundTaxBreakdown / CashMovement）の制約・enum のテスト。
class AccountingModelsTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      login_name: "acctmodel#{SecureRandom.hex(3)}",
      email: "acctmodel#{SecureRandom.hex(3)}@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "会計モデル店舗#{SecureRandom.hex(3)}", ascii_name: "acct#{SecureRandom.hex(3)}"[0, 16])
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @employee = @user.employees.create!(code: "E001", name: "田中一郎")
    @employee.stores << @store
  end

  def create_session(attrs = {})
    RegisterSession.create!({
      user: @user, store: @store, pos_token: @pos_token,
      business_date: Date.current, z_number: 1, status: :open,
      opened_at: Time.current, opening_employee: @employee, opening_float: 30000
    }.merge(attrs))
  end

  test "レジセッションを開設できる" do
    session = create_session
    assert session.open?
    assert_equal 30000, session.opening_float
  end

  test "同一端末で open セッションは同時に1つまで（DB部分一意制約）" do
    create_session
    assert_raises(ActiveRecord::RecordNotUnique) do
      # z_number の一意性を避けて open 重複だけを検証する
      session = RegisterSession.new(
        user: @user, store: @store, pos_token: @pos_token,
        business_date: Date.current, z_number: 2, status: :open,
        opened_at: Time.current, opening_float: 0
      )
      session.save!(validate: false)
    end
  end

  test "z_number は端末ごとに一意" do
    create_session(status: :closed, closed_at: Time.current, closing_counted_amount: 30000)
    dup = RegisterSession.new(
      user: @user, store: @store, pos_token: @pos_token,
      business_date: Date.current, z_number: 1, status: :open,
      opened_at: Time.current, opening_float: 0
    )
    assert_not dup.valid?
    assert dup.errors[:z_number].any?
  end

  test "精算済みセッションは readonly で更新できない" do
    session = create_session
    session.update!(
      status: :closed, closed_at: Time.current,
      closing_counted_amount: 35000, expected_cash_amount: 34000, cash_diff_amount: 1000
    )

    frozen = RegisterSession.find(session.id)
    assert frozen.readonly?
    assert_raises(ActiveRecord::ReadOnlyRecord) do
      frozen.update!(closing_counted_amount: 99999)
    end
  end

  test "CashMovement は種別と方向の整合を検証する" do
    movement = CashMovement.new(
      store: @store, pos_token: @pos_token, employee: @employee,
      kind: :pickup, direction: :inbound, amount: 1000, occurred_at: Time.current
    )
    assert_not movement.valid?
    assert movement.errors[:direction].any?

    movement.direction = :outbound
    assert movement.valid?
  end

  test "CashMovement.direction_for が種別に対応する方向を返す" do
    assert_equal "outbound", CashMovement.direction_for(:pickup)
    assert_equal "inbound",  CashMovement.direction_for(:replenishment)
    assert_equal "inbound",  CashMovement.direction_for(:misc_in)
    assert_equal "outbound", CashMovement.direction_for(:misc_out)
  end

  test "税率別内訳は (sale, tax_rate, tax_type) で一意" do
    sale = Sale.create!(
      user: @user, store: @store, pos_token: @pos_token,
      total_amount: 1100, payment_method: :cash,
      subtotal_ex_tax: 1000, tax_amount: 100
    )
    sale.sale_tax_breakdowns.create!(
      tax_rate: 10, tax_type: :inclusive,
      taxable_amount: 1100, amount_ex_tax: 1000, tax_amount: 100
    )
    dup = sale.sale_tax_breakdowns.build(
      tax_rate: 10, tax_type: :inclusive,
      taxable_amount: 550, amount_ex_tax: 500, tax_amount: 50
    )
    assert_not dup.valid?
  end

  test "既定値は現行挙動と一致する（内税・切捨て・completed）" do
    assert_equal "round_down", @user.tax_rounding_method
    product = @user.products.create!(code: "TX01", name: "税テスト", price: 100, tax_rate: 10)
    assert_equal "inclusive", product.tax_type

    sale = Sale.create!(
      user: @user, store: @store, pos_token: @pos_token,
      total_amount: 100, payment_method: :cash
    )
    assert_equal "completed", sale.status
  end

  test "登録番号はT+13桁のみ許容する" do
    @user.invoice_registration_number = "T1234567890123"
    assert @user.valid?

    @user.invoice_registration_number = "1234567890123"
    assert_not @user.valid?
  end
end
