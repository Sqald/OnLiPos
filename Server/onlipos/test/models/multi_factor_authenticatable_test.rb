require "test_helper"

class MultiFactorAuthenticatableTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      login_name: "mfamodel", email: "mfamodel@example.com",
      password: "Password1!", password_confirmation: "Password1!",
      first_name: "太郎", last_name: "鍵", user_type: :individual,
      confirmed_at: Time.current
    )
  end

  test "TOTP秘密鍵は暗号化して保存される" do
    secret = User.generate_otp_secret
    @user.enable_otp!(secret, nil)
    raw = User.where(id: @user.id).pick(:otp_secret_ciphertext)
    assert_not_includes raw, secret
    assert_equal secret, @user.reload.otp_secret
  end

  test "リカバリーコードは平文を保存せず、紛らわしい文字を含まない" do
    codes = @user.regenerate_recovery_codes!
    assert_equal 10, codes.size
    codes.each { |c| assert_match(/\A[A-HJKMNP-Z2-9]{5}-[A-HJKMNP-Z2-9]{5}\z/, c) }
    stored = @user.reload.mfa_recovery_code_digests
    assert_empty stored & codes
    assert @user.consume_recovery_code!(codes[3])
    assert_not @user.consume_recovery_code!(codes[3])
    assert_equal 9, @user.reload.recovery_codes_remaining
  end

  test "reset_mfa! で全ての要素が解除される" do
    @user.enable_otp!(User.generate_otp_secret, nil)
    @user.passkeys.create!(external_id: "abc", public_key: "pk", nickname: "PC")
    @user.regenerate_recovery_codes!
    assert @user.mfa_enabled?

    @user.reset_mfa!
    @user.reload
    assert_not @user.mfa_enabled?
    assert_equal 0, @user.recovery_codes_remaining
  end
end
