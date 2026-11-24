# 外部連携用のAPIキー。DBにはダイジェストだけを保存する
class ApiKey < ApplicationRecord
  include Auditable
  SCOPES = {
    "sales:read" => "売上・返品の参照", "products:read" => "商品の参照", "products:write" => "商品の登録・変更",
    "stocks:read" => "在庫の参照", "customers:read" => "会員の参照"
  }.freeze

  belongs_to :user
  attr_reader :token

  validates :name, presence: true
  validate { errors.add(:scopes, "を選択してください") if scopes.empty? || (scopes - SCOPES.keys).any? }
  before_create do
    @token = "olp_#{SecureRandom.base58(40)}"
    self.token_digest = self.class.digest(@token)
    self.token_hint = "olp_…#{@token.last(4)}"
  end

  scope :active, -> { where(revoked_at: nil) }

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  def self.authenticate(token)
    active.includes(:user).find_by(token_digest: digest(token)) if token.present?
  end

  def revoke! = update!(revoked_at: Time.current)
end
