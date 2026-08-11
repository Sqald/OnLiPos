# POS端末（レジ端末）。店舗に属し、端末単位でレシート連番・ジャーナル連番を採番する。
# 端末側はこの token（has_secure_token）で API 認証を行う。
class PosToken < ApplicationRecord
  # アソシエーション
  belongs_to :store
  belongs_to :provisioning, optional: true
  has_many :sales, dependent: :nullify
  has_many :cash_logs, dependent: :nullify
  has_many :register_sessions, dependent: :destroy
  has_many :cash_movements, dependent: :destroy

  has_secure_token :token
  has_secure_password

  # バリデーション
  validates :password, presence: true, on: :create
  validates :name, presence: true, uniqueness: { scope: :store_id }
  validates :ascii_name, presence: true, length: { in: 3..16 }, format: { with: /\A[a-zA-Z0-9]+\z/ }, uniqueness: { scope: :store_id, case_sensitive: false }

  validate :provisioning_must_belong_to_same_store

  private

  # provisioning が紐付く場合、その store と自身の store が一致することを検証する
  def provisioning_must_belong_to_same_store
    return if provisioning.nil? || store.nil?

    if provisioning.store_id != store_id
      errors.add(:provisioning_id, "は選択した店舗の設定のみ指定できます")
    end
  end
end
