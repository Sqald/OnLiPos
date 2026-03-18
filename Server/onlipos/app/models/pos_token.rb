class PosToken < ApplicationRecord
  belongs_to :store
  belongs_to :provisioning, optional: true
  has_many :sales, dependent: :nullify
  has_many :cash_logs, dependent: :nullify

  has_secure_token :token
  has_secure_password

  validates :password, presence: true, on: :create
  validates :name, presence: true, uniqueness: { scope: :store_id }
  validates :ascii_name, presence: true, length: { in: 3..16 }, format: { with: /\A[a-zA-Z0-9]+\z/ }, uniqueness: { scope: :store_id, case_sensitive: false }

  validate :provisioning_must_belong_to_same_store

  private

  def provisioning_must_belong_to_same_store
    return if provisioning.nil? || store.nil?

    if provisioning.store_id != store_id
      errors.add(:provisioning_id, "は選択した店舗の設定のみ指定できます")
    end
  end
end
