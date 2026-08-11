require "test_helper"

class DashboardProductsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      login_name: "dashproducttest",
      email: "dashproducttest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "商品",
      user_type: :individual,
      confirmed_at: Time.current
    )
    sign_in @user
  end

  test "sold_by_weight を指定して商品を登録できる" do
    post dashboard_products_path, params: {
      product: {
        code: "W001", name: "量り売り商品", price: 500, tax_rate: 8,
        sold_by_weight: "1"
      }
    }

    product = @user.products.find_by(code: "W001")
    assert product
    assert product.sold_by_weight?
  end

  test "sold_by_weight を指定しない場合は false のまま登録される" do
    post dashboard_products_path, params: {
      product: { code: "W002", name: "通常商品", price: 1000, tax_rate: 10 }
    }

    product = @user.products.find_by(code: "W002")
    assert product
    assert_not product.sold_by_weight?
  end

  test "sold_by_weight を更新できる" do
    product = @user.products.create!(code: "W003", name: "商品", price: 1000, tax_rate: 10)

    patch dashboard_product_path(product), params: {
      product: { sold_by_weight: "1" }
    }

    assert product.reload.sold_by_weight?
  end
end
