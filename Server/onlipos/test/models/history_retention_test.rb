require "test_helper"

# 売上・返品の履歴（いつ・どこで・誰が・何を）を保持するため、
# 履歴から参照されているマスタ（店舗・レジ・従業員・商品）は削除できないことを確認する。
class HistoryRetentionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      login_name: "retention", email: "retention@example.com",
      password: "Password1!", password_confirmation: "Password1!",
      first_name: "太郎", last_name: "保存", user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "保存店舗", ascii_name: "retstore")
    @pos = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @employee = @user.employees.create!(code: "H001", name: "保存太郎")
    @product = @user.products.create!(code: "H-P1", name: "保存商品", price: 100)
    @sale = Sale.create!(user: @user, store: @store, pos_token: @pos, employee: @employee,
                         total_amount: 100, payment_method: :cash)
    @sale.saledetails.create!(product: @product, product_name: @product.name, quantity: 1, unit_price: 100, subtotal: 100)
  end

  test "販売履歴のある商品は削除できない" do
    assert_not @product.destroy
    assert Product.exists?(@product.id)
  end

  test "担当履歴のある従業員は削除できない" do
    assert_not @employee.destroy
    assert Employee.exists?(@employee.id)
  end

  test "売上のあるレジ端末は削除できず、売上の端末記録も残る" do
    assert_not @pos.destroy
    assert_equal @pos.id, @sale.reload.pos_token_id
  end

  test "売上のある店舗は削除できず、売上も残る" do
    assert_not @store.destroy
    assert Sale.exists?(@sale.id)
    assert PosToken.exists?(@pos.id)
  end

  test "履歴のない商品・従業員は削除できる" do
    product = @user.products.create!(code: "H-P2", name: "未販売", price: 100)
    employee = @user.employees.create!(code: "H002", name: "未担当")
    assert product.destroy
    assert employee.destroy
  end
end
