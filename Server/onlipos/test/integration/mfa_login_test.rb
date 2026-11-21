require "test_helper"
require "webauthn/fake_client"

# ダッシュボードログインの2段階認証（MFA）必須化のテスト
class MfaLoginTest < ActionDispatch::IntegrationTest
  PASSWORD = "Password1!".freeze

  setup do
    @user = User.create!(
      login_name: "mfauser", email: "mfa@example.com",
      password: PASSWORD, password_confirmation: PASSWORD,
      first_name: "太郎", last_name: "二段", user_type: :individual,
      confirmed_at: Time.current
    )
  end

  def login_password(remember: false)
    post user_session_path, params: { user: { email: @user.email, password: PASSWORD, remember_me: remember ? "1" : "0" } }
  end

  def enable_totp!
    secret = User.generate_otp_secret
    @user.enable_otp!(secret, nil)
    secret
  end

  def signed_in_to_dashboard?
    get dashboard_root_path
    response.successful?
  end

  test "パスワードが正しくてもMFAを通るまではログインできない" do
    login_password
    assert_redirected_to user_mfa_path
    assert_not signed_in_to_dashboard?
    assert_redirected_to new_user_session_path
  end

  test "パスワードが違えば2段階目に進めない" do
    post user_session_path, params: { user: { email: @user.email, password: "wrong" } }
    assert_response :unprocessable_entity
    get user_mfa_path
    assert_redirected_to new_user_session_path
  end

  test "MFA未設定のユーザーは認証アプリを登録してからログインし、リカバリーコードが一度だけ表示される" do
    login_password
    get user_mfa_path
    assert_response :success
    assert_select "h2", "2段階認証の設定"
    assert_select "img.mfa-qr-svg[src^='data:image/svg+xml;base64,']"

    secret = session[:mfa_setup_secret]
    post user_mfa_totp_path, params: { code: "000000" }
    assert_redirected_to user_mfa_path
    assert_not @user.reload.otp_enabled?

    post user_mfa_totp_path, params: { code: ROTP::TOTP.new(secret).now }
    assert_redirected_to dashboard_security_recovery_codes_path
    assert @user.reload.otp_enabled?
    assert_equal 10, @user.recovery_codes_remaining

    get dashboard_security_recovery_codes_path
    assert_response :success
    assert_select "ul.mfa-codes li", 10
    get dashboard_security_recovery_codes_path
    assert_redirected_to dashboard_security_path
    assert signed_in_to_dashboard?
  end

  test "認証アプリのコードでログインでき、同じコードは再利用できない" do
    secret = enable_totp!
    code = ROTP::TOTP.new(secret).now

    login_password
    get user_mfa_path
    assert_select "h2", "2段階認証"
    post user_mfa_totp_path, params: { code: code }
    assert signed_in_to_dashboard?

    delete destroy_user_session_path
    login_password
    post user_mfa_totp_path, params: { code: code }
    assert_redirected_to user_mfa_path
    assert_not signed_in_to_dashboard?
  end

  test "リカバリーコードは1回だけ使える" do
    enable_totp!
    codes = @user.regenerate_recovery_codes!

    login_password
    post user_mfa_recovery_path, params: { recovery_code: codes.first.downcase.delete("-") }
    assert_redirected_to dashboard_security_path
    assert signed_in_to_dashboard?
    assert_equal 9, @user.reload.recovery_codes_remaining

    delete destroy_user_session_path
    login_password
    post user_mfa_recovery_path, params: { recovery_code: codes.first }
    assert_redirected_to user_mfa_path
    assert_not signed_in_to_dashboard?
  end

  test "2段階目を5回間違えるとパスワードからやり直しになる" do
    enable_totp!
    login_password
    5.times { post user_mfa_totp_path, params: { code: "000000" } }
    assert_redirected_to new_user_session_path
    get user_mfa_path
    assert_redirected_to new_user_session_path
  end

  test "パスワード確認から10分を過ぎると2段階目は無効" do
    secret = enable_totp!
    login_password
    travel 11.minutes do
      post user_mfa_totp_path, params: { code: ROTP::TOTP.new(secret).now }
      assert_redirected_to new_user_session_path
    end
  end

  test "MFAを通っていないログイン状態（導入前のセッション等）はログアウトさせられる" do
    Warden.on_next_request { |proxy| proxy.set_user(@user, scope: :user) }
    get dashboard_root_path
    assert_redirected_to new_user_session_path
    assert_not signed_in_to_dashboard?
  end

  test "ログインしたままにする: MFA後に発行されたCookieでブラウザ再起動後もログインできる" do
    secret = enable_totp!
    login_password(remember: true)
    post user_mfa_totp_path, params: { code: ROTP::TOTP.new(secret).now }
    remember = cookies["remember_user_token"]
    assert remember.present?

    browser = open_session
    browser.cookies["remember_user_token"] = remember
    browser.get dashboard_root_path
    assert browser.response.successful?
  end

  test "パスキーを登録してログインし、次回はパスキーで確認できる" do
    client = WebAuthn::FakeClient.new("http://www.example.com")

    login_password
    post user_mfa_passkey_options_path, as: :json
    assert_response :success
    options = response.parsed_body
    attestation = client.create(challenge: options["challenge"], rp_id: "www.example.com", user_verified: true)
    post user_mfa_passkey_path, params: { credential: attestation, nickname: "テストPC" }, as: :json
    assert_response :success
    assert_equal dashboard_security_recovery_codes_path, response.parsed_body["redirect"]
    assert_equal [ "テストPC" ], @user.passkeys.pluck(:nickname)
    assert signed_in_to_dashboard?

    delete destroy_user_session_path
    login_password
    post user_mfa_passkey_options_path, as: :json
    challenge = response.parsed_body["challenge"]
    assertion = client.get(challenge: challenge, rp_id: "www.example.com", user_verified: true)
    post user_mfa_passkey_path, params: { credential: assertion }, as: :json
    assert_response :success
    assert signed_in_to_dashboard?
    assert @user.passkeys.first.last_used_at.present?
  end

  test "ユーザー検証（生体認証/PIN）なしのパスキー応答は受け付けない" do
    client = WebAuthn::FakeClient.new("http://www.example.com")
    login_password
    post user_mfa_passkey_options_path, as: :json
    attestation = client.create(challenge: response.parsed_body["challenge"], rp_id: "www.example.com", user_verified: false)
    post user_mfa_passkey_path, params: { credential: attestation }, as: :json
    assert_response :unprocessable_entity
    assert_not @user.passkeys.exists?
    assert_not signed_in_to_dashboard?
  end

  test "最後の2段階認証の方法は削除できない" do
    enable_totp!
    sign_in_with_totp
    delete dashboard_security_totp_path
    assert_redirected_to dashboard_security_path
    assert @user.reload.otp_enabled?
  end

  private

  def sign_in_with_totp
    @user.update_column(:otp_last_used_timestep, nil)
    login_password
    post user_mfa_totp_path, params: { code: ROTP::TOTP.new(@user.otp_secret).now }
  end
end
