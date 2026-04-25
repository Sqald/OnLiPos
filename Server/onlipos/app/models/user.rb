class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :rememberable, :validatable

  has_many :stores, dependent: :destroy
  has_many :employees, dependent: :destroy
  has_many :devices, through: :shops
  has_many :products, dependent: :destroy
  has_many :product_bundles, dependent: :destroy
  has_many :provisionings, dependent: :destroy
  has_many :sales, dependent: :destroy

  # ユーザータイプの定義 (1: 個人, 2: 法人)
  enum :user_type, { individual: 1, corporate: 2 }

  # バリデーション
  validates :last_name, :first_name, :user_type, presence: true
  validates :login_name, presence: true, length: { in: 4..16 }, format: { with: /\A[a-zA-Z0-9]+\z/ }, uniqueness: { case_sensitive: false }
  validates :company_name, presence: true, if: :corporate?
  validates :company_name, absence: true, if: :individual?
end
