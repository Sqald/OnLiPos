# 発注の明細
class PurchaseOrderItem < ApplicationRecord
  belongs_to :purchase_order, inverse_of: :items
  belongs_to :product

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_cost, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate { errors.add(:product, "が不正です") if product && purchase_order && product.user_id != purchase_order.user_id }

  def remaining = quantity - received_quantity
end
