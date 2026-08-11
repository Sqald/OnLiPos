# 複数商品をまとめて販売するセット商品（バンドル）。構成品は ProductBundleItem 経由で参照する
class ProductBundle < ApplicationRecord
  # アソシエーション
  belongs_to :user
  has_many :product_bundle_items, dependent: :destroy
  has_many :products, through: :product_bundle_items

  enum :status, { active: 0, discontinued: 1 }

  # バリデーション
  validates :code, presence: true, uniqueness: { scope: :user_id }
  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }

  # status を日本語表示用の文字列に変換する
  def status_i18n
    status == "active" ? "有効" : "廃盤"
  end
end
