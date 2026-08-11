# 店舗ごとの商品在庫数。増減の履歴は StockMovement に記録される
class StoreStock < ApplicationRecord
  belongs_to :store
  belongs_to :product
  has_many :stock_movements, dependent: :destroy

  validates :quantity, numericality: { only_integer: true }
end
