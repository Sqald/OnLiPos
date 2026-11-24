# 外部システムへの通知先。本文は secret による HMAC-SHA256 署名（X-OnLiPos-Signature）付きで送る
class Webhook < ApplicationRecord
  include Auditable
  EVENTS = { "sale.created" => "会計の登録", "sale.voided" => "会計の取消", "refund.created" => "返品の登録", "stock.low" => "在庫の不足" }.freeze
  MAX_FAILURES = 20

  belongs_to :user

  before_validation(on: :create) { self.secret = SecureRandom.hex(32) if secret_ciphertext.blank? }
  validates :url, presence: true, length: { maximum: 2000 }
  validate :url_must_be_public_https
  validate { errors.add(:events, "を選択してください") if events.empty? || (events - EVENTS.keys).any? }

  scope :enabled, -> { where(active: true) }

  # 該当イベントの通知先すべてに送信を予約する
  def self.publish(account, event, payload)
    enabled.where(user: account).where("? = ANY(events)", event).ids.each { |id| WebhookDeliveryJob.perform_later(id, event, payload) }
  rescue => e
    Rails.logger.error "[Webhook] publish failed: #{e.class} #{e.message}"
  end

  def secret = encryptor.decrypt_and_verify(secret_ciphertext)
  def secret=(value)
    self.secret_ciphertext = encryptor.encrypt_and_sign(value)
  end

  def sign(body, timestamp) = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")

  # 内部ネットワークへの送信（SSRF）を防ぐ。名前解決の結果がすべて公開アドレスであること
  def self.resolve_public(host)
    addresses = Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map { |a| IPAddr.new(a.ip_address) }.uniq
    addresses if addresses.any? && addresses.all? { |ip| public_address?(ip) }
  rescue SocketError, IPAddr::Error
    nil
  end

  BLOCKED = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15
               224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 64:ff9b::/96 fc00::/7 fe80::/10 ff00::/8].map { |range| IPAddr.new(range) }.freeze

  def self.public_address?(ip)
    ip = ip.native if ip.ipv4_mapped?
    BLOCKED.none? { |range| range.family == ip.family && range.include?(ip) }
  end

  private

  def encryptor
    key = Rails.application.key_generator.generate_key("onlipos/webhooks/secret", ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key)
  end

  def url_must_be_public_https
    uri = URI.parse(url.to_s)
    errors.add(:url, "は https:// で始まるURLを指定してください") unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    errors.add(:url, "が不正です")
  end
end
