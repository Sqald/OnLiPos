class RefundDetail < ApplicationRecord
  belongs_to :refund
  belongs_to :saledetail
  belongs_to :product

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :unit_price, :subtotal, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
