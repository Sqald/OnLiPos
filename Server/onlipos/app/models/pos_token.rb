# POS端末（レジ端末）。店舗に属し、端末単位でレシート連番・ジャーナル連番を採番する。
# 端末側はこの token（has_secure_token）で API 認証を行う。
class PosToken < ApplicationRecord
  include Auditable
  # アソシエーション
  belongs_to :store
  belongs_to :provisioning, optional: true
  # 売上・返品の「どのレジで」を失わないよう、履歴のある端末は削除できない
  has_many :sales, dependent: :restrict_with_error
  has_many :refunds, dependent: :restrict_with_error
  has_many :journal_entries, dependent: :restrict_with_error
  has_one :customer_display, dependent: :delete
  has_many :operator_approvals, dependent: :delete_all
  has_many :cash_logs, dependent: :nullify
  has_many :register_sessions, dependent: :destroy
  has_many :cash_movements, dependent: :destroy

  # 端末の認証トークン。DBにはダイジェストだけを保存する。平文は発行直後のインスタンスでのみ参照できる
  attr_reader :token

  scope :enabled, -> { where(disabled_at: nil) }

  before_create :issue_token

  def self.digest_token(token) = Digest::SHA256.hexdigest(token.to_s)

  def self.find_by_token(token)
    find_by(token_digest: digest_token(token)) if token.present?
  end

  # 新しいトークンを発行して保存し、平文を返す（以前のトークンは無効になる）
  def regenerate_token
    issue_token
    update_columns(token_digest: token_digest, updated_at: Time.current)
    token
  end

  # 端末の遠隔停止（紛失・盗難・退店時）。履歴は残したままAPIを使えなくする
  def disable!(reason = nil)
    update!(disabled_at: Time.current, disabled_reason: reason.presence)
    OperatorApproval.where(pos_token_id: id).active.update_all(expires_at: Time.current)
  end

  def enable! = update!(disabled_at: nil, disabled_reason: nil)

  def disabled? = disabled_at.present?

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

  # 端末の認証状態: :disabled（停止中）/ :authenticated（認証済み）/ :pending（パスワード有効・未認証）/ :expired（期限切れ）
  def password_status
    return :disabled if disabled?
    return :authenticated if password_digest.blank?
    password_expired? ? :expired : :pending
  end

  private

  def issue_token
    @token = SecureRandom.base58(40)
    self.token_digest = self.class.digest_token(@token)
  end

  # provisioning が紐付く場合、その store と自身の store が一致することを検証する
  def provisioning_must_belong_to_same_store
    return if provisioning.nil? || store.nil?

    if provisioning.store_id != store_id
      errors.add(:provisioning_id, "は選択した店舗の設定のみ指定できます")
    end
  end
end
