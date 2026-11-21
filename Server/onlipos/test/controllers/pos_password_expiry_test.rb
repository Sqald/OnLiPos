require "test_helper"

# POS端末の初期パスワード（管理画面で生成）は2週間で失効し、認証済みの端末トークンは無期限
class PosPasswordExpiryTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      login_name: "posexpiry", email: "posexpiry@example.com",
      password: "Password1!", password_confirmation: "Password1!",
      first_name: "太郎", last_name: "端末", user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "期限店舗", ascii_name: "expstore")
    @pos = @store.pos_tokens.build(name: "レジ1", ascii_name: "pos1")
    @password = @pos.issue_initial_password
    @pos.save!
  end

  def pos_login(password = @password)
    post "/api/v1/pos_devices/login",
         params: { pos: { userName: "posexpiry", storeName: "expstore", posName: "pos1", password: password } },
         as: :json
  end

  test "生成したパスワードの期限は2週間" do
    assert_in_delta 14.days.from_now.to_i, @pos.password_expires_at.to_i, 5
    assert_equal :pending, @pos.password_status
  end

  test "期限内なら認証でき、認証後はパスワードが消えトークンは期限なしで使える" do
    token = nil
    travel 13.days do
      pos_login
      assert_response :ok
      token = response.parsed_body["token"]
      @pos.reload
      assert_nil @pos.password_digest
      assert_nil @pos.password_expires_at
      assert_equal :authenticated, @pos.password_status
    end

    travel 400.days do
      get "/api/v1/sales/summary", headers: { "Authorization" => "Bearer #{token}" }
      assert_not_equal 401, response.status
    end
  end

  test "期限切れのパスワードでは認証できない" do
    travel 15.days do
      pos_login
      assert_response :unauthorized
      assert_match "有効期限", response.parsed_body["message"]
      assert @pos.reload.password_digest.present?
      assert_equal :expired, @pos.password_status
    end
  end

  test "管理画面でパスワードを再設定すると新しい2週間の期限が付く" do
    sign_in @user
    travel 20.days do
      patch dashboard_pos_device_update_password_path(@pos)
      assert_redirected_to dashboard_root_path
      new_password = flash[:notice][/新パスワード: (\d{6})/, 1]
      assert new_password
      assert_in_delta 14.days.from_now.to_i, @pos.reload.password_expires_at.to_i, 5
      pos_login(new_password)
      assert_response :ok
    end
  end
end
