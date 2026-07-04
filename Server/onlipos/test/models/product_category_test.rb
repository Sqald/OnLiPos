require "test_helper"

class ProductCategoryTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      login_name: "catuser",
      email: "cat@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "花子",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
  end

  test "名前と user_id があれば有効" do
    cat = ProductCategory.new(user: @user, name: "食品", display_order: 1)
    assert cat.valid?
  end

  test "名前が空なら無効" do
    cat = ProductCategory.new(user: @user, name: "")
    assert_not cat.valid?
    assert cat.errors[:name].any?
  end

  test "同一ユーザー内で名前は一意でなければならない" do
    @user.product_categories.create!(name: "飲料", display_order: 1)
    dup = ProductCategory.new(user: @user, name: "飲料")
    assert_not dup.valid?
    assert dup.errors[:name].any?
  end

  test "別のユーザーなら同名カテゴリを作成できる" do
    other_user = User.create!(
      login_name: "othercat",
      email: "other@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "次郎",
      last_name: "他社",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @user.product_categories.create!(name: "菓子")
    cat2 = other_user.product_categories.build(name: "菓子")
    assert cat2.valid?
  end

  test "商品に紐付けできる" do
    cat = @user.product_categories.create!(name: "生鮮")
    product = @user.products.create!(code: "F001", name: "りんご", price: 200, tax_rate: 8)
    product.update!(product_category: cat)
    assert_equal cat, product.product_category
    assert_includes cat.products, product
  end

  test "カテゴリを削除すると商品の category_id が NULL になる" do
    cat = @user.product_categories.create!(name: "削除テスト")
    product = @user.products.create!(code: "D001", name: "商品D", price: 100, tax_rate: 10, product_category: cat)
    cat.destroy
    assert_nil product.reload.product_category_id
  end

  test "display_order が負の場合は無効" do
    cat = ProductCategory.new(user: @user, name: "テスト", display_order: -1)
    assert_not cat.valid?
    assert cat.errors[:display_order].any?
  end
end
