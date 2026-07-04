require "test_helper"

class SaleTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      login_name: "testuser",
      email: "test@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "テスト店舗", ascii_name: "teststore")
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @employee = @user.employees.create!(code: "E001", name: "田中一郎")
    @product = @user.products.create!(code: "P001", name: "商品A", price: 1000, tax_rate: 10)
  end

  # ---- 担当者紐付け ----

  test "担当者なしで売上を作成できる" do
    sale = Sale.new(
      user: @user,
      store: @store,
      pos_token: @pos_token,
      total_amount: 1100,
      subtotal_ex_tax: 1000,
      tax_amount: 100
    )
    assert sale.valid?
    assert_nil sale.employee
  end

  test "担当者ありで売上を作成できる" do
    sale = Sale.create!(
      user: @user,
      store: @store,
      pos_token: @pos_token,
      employee: @employee,
      total_amount: 1100,
      subtotal_ex_tax: 1000,
      tax_amount: 100
    )
    assert_equal @employee, sale.employee
    assert_equal @employee.id, Sale.find(sale.id).employee_id
  end

  # ---- 割引合計 ----

  test "割引合計は 0 以上でなければならない" do
    sale = Sale.new(
      user: @user, store: @store, total_amount: 0, total_discount: -1
    )
    assert_not sale.valid?
    assert sale.errors[:total_discount].any?
  end

  test "割引合計のデフォルト値は 0" do
    sale = Sale.create!(
      user: @user, store: @store, pos_token: @pos_token,
      total_amount: 1100, subtotal_ex_tax: 1000, tax_amount: 100
    )
    assert_equal 0, sale.total_discount
  end

  # ---- レシート番号 ----

  test "POS端末ありの場合は連番ベースのレシート番号が生成される" do
    sale = Sale.create!(
      user: @user, store: @store, pos_token: @pos_token,
      total_amount: 1100
    )
    assert_match(/\Atestuser-teststore-\d+-\d{8}\z/, sale.receipt_number)
  end

  test "POS端末なしの場合は MANUAL ベースのレシート番号が生成される" do
    sale = Sale.create!(
      user: @user, store: @store,
      total_amount: 500
    )
    assert_includes sale.receipt_number, "MANUAL"
  end

  test "同一 POS トークンから複数回売上を作成すると連番が増加する" do
    sale1 = Sale.create!(user: @user, store: @store, pos_token: @pos_token, total_amount: 100)
    sale2 = Sale.create!(user: @user, store: @store, pos_token: @pos_token, total_amount: 200)

    seq1 = sale1.receipt_number.split("-").last.to_i
    seq2 = sale2.receipt_number.split("-").last.to_i
    assert seq2 > seq1, "連番が増加していない: #{seq1} >= #{seq2}"
  end
end
