require "test_helper"

# Content Security Policy の回帰テスト（未ログイン・セッションCookieなしの初回訪問）
class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  test "初回訪問（セッションCookieなし）でも nonce が空にならず、スクリプトが実行できる" do
    get new_user_session_path

    assert_response :ok
    script_src = response.headers["Content-Security-Policy"][/script-src [^;]*/]
    assert_match(/'nonce-[^']+'/, script_src)
    assert_no_match(/nonce=""/, response.body)

    # ヘッダーの nonce とページ内 importmap タグの nonce が一致していること
    nonce = script_src[/'nonce-([^']+)'/, 1]
    assert_includes response.body, %(nonce="#{nonce}")
  end
end
