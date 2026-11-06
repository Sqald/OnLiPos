require "test_helper"

# POS端末ログインのブルートフォース対策。
# 第三者がわざと失敗させても、別の接続元からの正規ログインはロックされないことを確認する。
class PosLoginThrottleTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "throttle",
      email: "throttle@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "スロットル店", ascii_name: "throttlestore")
    @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    # テスト環境は null_store のため、失敗回数を数えられるようメモリキャッシュに差し替える
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @original_cache
  end

  def attempt(password, ip)
    post "/api/v1/pos_devices/login",
         params: { pos: { userName: "throttle", storeName: "throttlestore", posName: "pos1", password: password } },
         env: { "REMOTE_ADDR" => ip },
         as: :json
  end

  test "同じ接続元から10回失敗するとロックされるが、別の接続元からはログインできる" do
    10.times { attempt("wrong", "203.0.113.10") }
    assert_response :unauthorized

    attempt("PosPass1!", "203.0.113.10")
    assert_response :too_many_requests

    attempt("PosPass1!", "198.51.100.20")
    assert_response :ok
  end
end
