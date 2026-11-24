# 棚卸の明細
class StocktakeItem < ApplicationRecord
  belongs_to :stocktake
  belongs_to :product
  belongs_to :employee, optional: true

  validates :counted_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # 実数と帳簿の差（確定前は現在の在庫との差）
  def difference = counted_quantity - expected
  def expected = expected_quantity || StoreStock.find_by(store_id: stocktake.store_id, product_id: product_id)&.quantity.to_i
  def difference_amount = product.cost_price ? difference * product.cost_price : nil
end
