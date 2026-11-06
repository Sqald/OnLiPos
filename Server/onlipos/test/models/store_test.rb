require "test_helper"

class StoreTest < ActiveSupport::TestCase
  def create_user(login_name)
    User.create!(
      login_name: login_name,
      email: "#{login_name}@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
  end

  test "店舗名は同一ユーザー内で一意" do
    user = create_user("storeuniq1")
    user.stores.create!(name: "本店", ascii_name: "honten")
    dup = user.stores.build(name: "本店", ascii_name: "honten2")
    assert_not dup.valid?
    assert dup.errors[:name].any?
  end

  test "別ユーザーなら同名の店舗を作成できる" do
    create_user("storeuniq2").stores.create!(name: "本店", ascii_name: "honten")
    other = create_user("storeuniq3").stores.build(name: "本店", ascii_name: "honten")
    assert other.valid?
  end
end
