require "test_helper"

class SaledetailTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      login_name: "detailtest",
      email: "detailtest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "花子",
      last_name: "明細",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "明細店舗", ascii_name: "detailstore")
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "dp1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @product = @user.products.create!(code: "D001", name: "明細商品", price: 1000, tax_rate: 10)
    @sale = Sale.create!(
      user: @user, store: @store, pos_token: @pos_token, total_amount: 1100
    )
  end

  test "割引なしで明細を作成できる" do
    detail = @sale.saledetails.create!(
      product: @product, product_name: @product.name,
      quantity: 1, unit_price: 1000, subtotal: 1000,
      tax_rate: 10, tax_amount: 100
    )
    assert_equal 0, detail.discount_amount
    assert_nil detail.original_unit_price
  end

  test "割引ありで明細を作成できる" do
    detail = @sale.saledetails.create!(
      product: @product, product_name: @product.name,
      quantity: 2, unit_price: 800, subtotal: 1600,
      tax_rate: 10, tax_amount: 145,
      original_unit_price: 1000,
      discount_amount: 400  # (1000 - 800) * 2
    )
    assert_equal 400, detail.discount_amount
    assert_equal 1000, detail.original_unit_price
  end

  test "discount_amount のデフォルトは 0" do
    detail = @sale.saledetails.build(
      product: @product, product_name: "商品",
      quantity: 1, unit_price: 500, subtotal: 500,
      tax_rate: 10, tax_amount: 45
    )
    assert_equal 0, detail.discount_amount
  end
end
