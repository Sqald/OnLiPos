# 企業アカウント（OnLiPosの契約単位）。ダッシュボードにログインする管理者本体であり、
# 店舗・商品・従業員・売上などほぼ全てのデータの起点となる。Devise で認証する。
class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :rememberable, :validatable

  has_many :stores, dependent: :destroy
  has_many :employees, dependent: :destroy
  has_many :devices, through: :shops
  has_many :products, dependent: :destroy
  has_many :product_categories, dependent: :destroy
  has_many :product_bundles, dependent: :destroy
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

  # バリデーション
  validates :last_name, :first_name, :user_type, presence: true
  validates :login_name, presence: true, length: { in: 4..16 }, format: { with: /\A[a-zA-Z0-9]+\z/ }, uniqueness: { case_sensitive: false }
  validates :company_name, presence: true, if: :corporate?
  validates :company_name, absence: true, if: :individual?
end
