# 認証アプリ（TOTP）による2段階目の認証。User（ダッシュボード）と Admin（コントロールセンター）で共用する。
# 必要な列: otp_secret_ciphertext, otp_enabled_at, otp_last_used_timestep
module TotpAuthenticatable
  extend ActiveSupport::Concern

  OTP_ISSUER = "OnLiPos".freeze

  class_methods do
    # TOTP 秘密鍵の暗号化に使う暗号器（secret_key_base から導出した鍵を使う）
    def otp_secret_encryptor
      @otp_secret_encryptor ||= begin
        key = Rails.application.key_generator.generate_key("onlipos/#{table_name}/otp_secret", ActiveSupport::MessageEncryptor.key_len)
        ActiveSupport::MessageEncryptor.new(key)
      end
    end

    def generate_otp_secret = ROTP::Base32.random
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
    ROTP::TOTP.new(secret, issuer: OTP_ISSUER).provisioning_uri(otp_account_name)
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

  # ログイン時のコード検証。一度使ったコード（同じ時間枠以前）は再利用できない。
  # 同じコードの同時送信でも片方だけ成功するよう、条件付き更新で確定する
  def verify_otp(code)
    return false unless otp_enabled?
    timestamp = TotpAuthenticatable.verify_totp(otp_secret, code, after: otp_last_used_timestep)
    return false unless timestamp

    updated = self.class.where(id: id)
                  .where("otp_last_used_timestep IS NULL OR otp_last_used_timestep < ?", timestamp)
                  .update_all(otp_last_used_timestep: timestamp)
    self.otp_last_used_timestep = timestamp
    clear_attribute_changes([ :otp_last_used_timestep ])
    updated == 1
  end
end
