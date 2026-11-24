# ダッシュボードログインの多要素認証（MFA）。User に include する。
#
# 2段階目の要素は次のいずれか（両方登録してもよい）。ログインには最低1つの登録が必須:
#   - 認証アプリ（TOTP: Google Authenticator / Microsoft Authenticator 等の6桁コード）
#   - パスキー（WebAuthn。端末の生体認証・PIN 等）
# 端末紛失に備えて使い捨てのリカバリーコードを発行する（平文は発行時に一度だけ表示し、ダイジェストのみ保存）。
module MultiFactorAuthenticatable
  extend ActiveSupport::Concern
  include TotpAuthenticatable

  RECOVERY_CODE_COUNT = 10
  # 読み間違えやすい文字（0/O, 1/I/L）を除いた文字セット
  RECOVERY_CODE_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789".chars.freeze

  included do
    has_many :passkeys, class_name: "UserPasskey", dependent: :destroy
  end

  class_methods do
    # リカバリーコードのダイジェスト。DBだけが漏れても総当たりできないよう、アプリの鍵を使う
    def recovery_code_digest(code)
      key = Rails.application.key_generator.generate_key("onlipos/users/recovery_code", 32)
      "v2:" + OpenSSL::HMAC.hexdigest("SHA256", key, normalize_recovery_code(code))
    end

    # 鍵を使わない旧形式（発行済みのコードの照合用）
    def legacy_recovery_code_digest(code)
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

  def otp_account_name = email

  # 登録前の秘密鍵でコードを検証する
  def self.verify_totp(...) = TotpAuthenticatable.verify_totp(...)

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
    digests = [ self.class.recovery_code_digest(code), self.class.legacy_recovery_code_digest(code) ]
    consumed = false
    with_lock do
      matched = mfa_recovery_code_digests & digests
      if matched.any?
        update!(mfa_recovery_code_digests: mfa_recovery_code_digests - matched)
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
      revoke_sessions!
    end
  end

  # WebAuthn のユーザーハンドル（初回のパスキー登録時に払い出す）
  def ensure_webauthn_id!
    update!(webauthn_id: WebAuthn.generate_user_id) if webauthn_id.blank?
    webauthn_id
  end
end
