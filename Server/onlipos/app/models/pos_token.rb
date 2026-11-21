# POS端末（レジ端末）。店舗に属し、端末単位でレシート連番・ジャーナル連番を採番する。
# 端末側はこの token（has_secure_token）で API 認証を行う。
class PosToken < ApplicationRecord
  # アソシエーション
  belongs_to :store
  belongs_to :provisioning, optional: true
  # 売上・返品の「どのレジで」を失わないよう、履歴のある端末は削除できない
  has_many :sales, dependent: :restrict_with_error
  has_many :refunds, dependent: :restrict_with_error
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

  # 管理画面で生成する初期パスワードの有効期限。
  # 端末がこのパスワードで認証すると、パスワードは消去され以後はトークン（無期限）で認証する
  INITIAL_PASSWORD_TTL = 2.weeks

  # 6桁の初期パスワードを生成して設定し、平文を返す（保存は呼び出し側で行う）
  def issue_initial_password
    generated = SecureRandom.random_number(100000..999999).to_s
    self.password = generated
    self.password_confirmation = generated
    self.password_expires_at = INITIAL_PASSWORD_TTL.from_now
    generated
  end

  # 初期パスワードの期限切れか（期限なし = 旧データは期限切れ扱いにしない）
  def password_expired?
    password_expires_at.present? && password_expires_at <= Time.current
  end

  # 端末の認証状態: :authenticated（認証済み）/ :pending（パスワード有効・未認証）/ :expired（期限切れ）
  def password_status
    return :authenticated if password_digest.blank?
    password_expired? ? :expired : :pending
  end

  private

  # provisioning が紐付く場合、その store と自身の store が一致することを検証する
  def provisioning_must_belong_to_same_store
    return if provisioning.nil? || store.nil?

    if provisioning.store_id != store_id
      errors.add(:provisioning_id, "は選択した店舗の設定のみ指定できます")
    end
  end
end
