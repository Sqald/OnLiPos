# ダッシュボードログインの多要素認証（MFA）。User に include する。
#
# 2段階目の要素は次のいずれか（両方登録してもよい）。ログインには最低1つの登録が必須:
#   - 認証アプリ（TOTP: Google Authenticator / Microsoft Authenticator 等の6桁コード）
#   - パスキー（WebAuthn。端末の生体認証・PIN 等）
# 端末紛失に備えて使い捨てのリカバリーコードを発行する（平文は発行時に一度だけ表示し、ダイジェストのみ保存）。
module MultiFactorAuthenticatable
  extend ActiveSupport::Concern

  OTP_ISSUER = "OnLiPos".freeze
  RECOVERY_CODE_COUNT = 10
  # 読み間違えやすい文字（0/O, 1/I/L）を除いた文字セット
  RECOVERY_CODE_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789".chars.freeze

  included do
    has_many :passkeys, class_name: "UserPasskey", dependent: :destroy
  end

  class_methods do
    # TOTP 秘密鍵の暗号化に使う暗号器（secret_key_base から導出した鍵を使う）
    def otp_secret_encryptor
      @otp_secret_encryptor ||= begin
        key = Rails.application.key_generator.generate_key("onlipos/users/otp_secret", ActiveSupport::MessageEncryptor.key_len)
        ActiveSupport::MessageEncryptor.new(key)
      end
    end

    def generate_otp_secret = ROTP::Base32.random

    def recovery_code_digest(code)
      Digest::SHA256.hexdigest(normalize_recovery_code(code))
    end

    def normalize_recovery_code(code)
      code.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    end
  end

  # MFA が設定済みか（ログインに必要な2段階目の要素が1つ以上あるか）
  def mfa_enabled?
    otp_enabled? || passkeys.exists?
  end

  def otp_enabled?
    otp_enabled_at.present? && otp_secret_ciphertext.present?
  end

  def otp_secret
    return nil if otp_secret_ciphertext.blank?
    self.class.otp_secret_encryptor.decrypt_and_verify(otp_secret_ciphertext)
  end

  def otp_secret=(value)
    self.otp_secret_ciphertext = value.presence && self.class.otp_secret_encryptor.encrypt_and_sign(value)
  end

  # 認証アプリ登録用の otpauth:// URI（QRコードにする）
  def otp_provisioning_uri(secret)
    ROTP::TOTP.new(secret, issuer: OTP_ISSUER).provisioning_uri(email)
  end

  # 登録前の秘密鍵でコードを検証する（登録時の確認用）
  def self.verify_totp(secret, code, after: nil)
    return nil unless code.to_s.strip.match?(/\A\d{6}\z/)
    ROTP::TOTP.new(secret, issuer: OTP_ISSUER).verify(code.to_s.strip, drift_behind: 30, drift_ahead: 30, after: after)
  end

  # 認証アプリを有効化する（登録時に1回コードを確認済みであること）
  def enable_otp!(secret, verified_at)
    update!(otp_secret: secret, otp_enabled_at: Time.current, otp_last_used_timestep: verified_at)
  end

  def disable_otp!
    update!(otp_secret_ciphertext: nil, otp_enabled_at: nil, otp_last_used_timestep: nil)
  end

  # ログイン時のコード検証。一度使ったコード（同じ時間枠以前）は再利用できない
  def verify_otp(code)
    return false unless otp_enabled?
    timestamp = MultiFactorAuthenticatable.verify_totp(otp_secret, code, after: otp_last_used_timestep)
    return false unless timestamp
    update_column(:otp_last_used_timestep, timestamp)
    true
  end

  # リカバリーコードを作り直し、平文の一覧を返す（以前のコードは無効になる）
  def regenerate_recovery_codes!
    codes = Array.new(RECOVERY_CODE_COUNT) do
      raw = Array.new(10) { RECOVERY_CODE_CHARS[SecureRandom.random_number(RECOVERY_CODE_CHARS.size)] }.join
      "#{raw[0, 5]}-#{raw[5, 5]}"
    end
    update!(mfa_recovery_code_digests: codes.map { |c| self.class.recovery_code_digest(c) })
    codes
  end

  def recovery_codes_remaining
    mfa_recovery_code_digests.size
  end

  # リカバリーコードでの認証。使ったコードは消費する（同時使用でも二重に使えないよう行ロックする）
  def consume_recovery_code!(code)
    return false if self.class.normalize_recovery_code(code).length != 10
    digest = self.class.recovery_code_digest(code)
    consumed = false
    with_lock do
      if mfa_recovery_code_digests.include?(digest)
        update!(mfa_recovery_code_digests: mfa_recovery_code_digests - [ digest ])
        consumed = true
      end
    end
    consumed
  end

  # MFA を全て解除する（管理者による本人確認後のリセット用）。次回ログイン時に再設定が必要になる
  def reset_mfa!
    transaction do
      passkeys.destroy_all
      update!(otp_secret_ciphertext: nil, otp_enabled_at: nil, otp_last_used_timestep: nil,
              mfa_recovery_code_digests: [])
    end
  end

  # WebAuthn のユーザーハンドル（初回のパスキー登録時に払い出す）
  def ensure_webauthn_id!
    update!(webauthn_id: WebAuthn.generate_user_id) if webauthn_id.blank?
    webauthn_id
  end
end
