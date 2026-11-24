# 企業アカウント（OnLiPosの契約単位）。ダッシュボードにログインする管理者本体であり、
# 店舗・商品・従業員・売上などほぼ全てのデータの起点となる。Devise で認証する。
class User < ApplicationRecord
  include Auditable

  def audit_name = display_name
  devise :database_authenticatable, :registerable, :rememberable, :validatable, :timeoutable
  # ダッシュボードログインの多要素認証（認証アプリ / パスキー / リカバリーコード）
  include MultiFactorAuthenticatable

  has_many :stores, dependent: :destroy
  has_many :employees, dependent: :destroy
  has_many :products, dependent: :destroy
  has_many :product_categories, dependent: :destroy
  has_many :product_bundles, dependent: :destroy
  has_many :option_groups, dependent: :destroy
  has_many :scheduled_product_changes, dependent: :delete_all
  has_many :product_imports, dependent: :delete_all
  has_many :customers, dependent: :restrict_with_error
  has_many :coupons, dependent: :restrict_with_error
  has_many :promotions, dependent: :destroy
  has_many :purchase_orders, dependent: :restrict_with_error
  has_many :suppliers, dependent: :destroy
  has_many :stocktakes, dependent: :restrict_with_error
  has_many :api_keys, dependent: :destroy
  has_many :webhooks, dependent: :destroy
  has_many :provisionings, dependent: :destroy
  has_many :sales, dependent: :destroy

  # ユーザータイプの定義 (1: 個人, 2: 法人)
  enum :user_type, { individual: 1, corporate: 2 }

  # 消費税の端数処理方式（0: 切捨て = 現行既定, 1: 四捨五入, 2: 切上げ）。
  # インボイスの「1レシートにつき税率ごとに端数処理1回」はこの方式で行う。
  enum :tax_rounding_method, { round_down: 0, round_half_up: 1, round_up: 2 }, prefix: :tax

  # 適格請求書発行事業者登録番号（T+13桁）。未登録（免税事業者等）は空欄可
  validates :invoice_registration_number,
            format: { with: /\AT\d{13}\z/, message: "はT+数字13桁で入力してください" },
            allow_blank: true

  # ── 契約アカウントとメンバー ──
  # owner_id のないユーザーが契約アカウント本体。メンバーは owner のデータを role の範囲で操作する
  belongs_to :owner, class_name: "User", optional: true
  has_many :members, class_name: "User", foreign_key: :owner_id, dependent: :destroy, inverse_of: :owner
  has_many :audit_logs, dependent: :delete_all

  # owner: すべて / manager: 店舗運営全般（メンバー・契約設定を除く） / viewer: 閲覧のみ
  enum :role, { owner: 0, manager: 1, viewer: 2 }, prefix: true
  validate :role_matches_ownership

  # データの持ち主となる契約アカウント
  def account = owner || self

  def member? = owner_id.present?

  def display_name = [ last_name, first_name ].compact_blank.join(" ").presence || login_name

  # ── 利用停止・セッション ──
  def suspended? = account.suspended_at.present?

  # Devise: 停止中の契約（またはそのメンバー）はログインできない
  def active_for_authentication?
    super && !suspended?
  end

  def inactive_message
    suspended? ? :suspended : super
  end

  # Devise のセッション・Remember Cookie はこの値と照合される。session_version を進めると全端末でログアウトになる
  def authenticatable_salt
    session_version.to_i.zero? ? super : "#{super}:#{session_version}"
  end

  def revoke_sessions!
    increment!(:session_version)
  end

  # 何円ごとに1ポイントを付与するか（0 = ポイントを使わない）。1ポイント = 1円
  validates :point_yen_per_point, numericality: { only_integer: true, in: 0..1_000_000 }
  validates :receipt_footer, length: { maximum: 200 }

  # バリデーション
  validates :last_name, :first_name, :user_type, presence: true
  validates :login_name, presence: true, length: { in: 4..16 }, format: { with: /\A[a-zA-Z0-9]+\z/ }, uniqueness: { case_sensitive: false }
  validates :company_name, presence: true, if: :corporate?
  validates :company_name, absence: true, if: :individual?
  private

  def role_matches_ownership
    errors.add(:role, "が不正です") if member? == role_owner?
    errors.add(:owner, "にはメンバーを指定できません") if owner&.member?
  end
end
