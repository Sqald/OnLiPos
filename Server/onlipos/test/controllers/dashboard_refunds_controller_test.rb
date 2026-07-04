require "test_helper"

class DashboardRefundsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      login_name: "refundlisttest",
      email: "refundlisttest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "テスト店舗", ascii_name: "refundliststore")
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @product = @user.products.create!(code: "P001", name: "商品A", price: 1000, tax_rate: 10)

    @sale = Sale.create!(
      user: @user, store: @store, pos_token: @pos_token,
      total_amount: 1100, payment_method: :cash,
      subtotal_ex_tax: 1000, tax_amount: 100
    )
    @saledetail = @sale.saledetails.create!(
      product: @product, product_name: @product.name,
      quantity: 1, unit_price: 1100, subtotal: 1100,
      tax_rate: 10, tax_amount: 100
    )
    @refund = Refund.create!(
      sale: @sale, store: @store, user: @user, pos_token: @pos_token,
      total_amount: 1100
    )
    @refund.refund_details.create!(
      saledetail: @saledetail, product_id: @product.id,
      product_name: @product.name, quantity: 1,
      unit_price: 1100, subtotal: 1100
    )

    sign_in @user
  end

  test "返品一覧が表示できる（検索実行時）" do
    get dashboard_refunds_path, params: { store_id: @store.id }
    assert_response :success
    assert_includes response.body, @refund.refund_receipt_number
  end

  test "返品詳細が表示できる" do
    get dashboard_refund_path(@refund)
    assert_response :success
    assert_includes response.body, @refund.refund_receipt_number
  end

  test "他ユーザーの返品詳細は表示できない" do
    other = User.create!(
      login_name: "refundlistother",
      email: "refundlistother@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "次郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    sign_in other

    get dashboard_refund_path(@refund)
    assert_redirected_to dashboard_root_path
  end
end
