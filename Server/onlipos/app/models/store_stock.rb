class StoreStock < ApplicationRecord
  belongs_to :store
  belongs_to :product
  has_many :stock_movements, dependent: :destroy

  validates :quantity, numericality: { greater_than_or_equal_to: 0, message: "は0以上である必要があります（在庫不足）" }
end
