class StockMovement < ApplicationRecord
  belongs_to :store
  belongs_to :product
  belongs_to :store_stock
  belongs_to :sale, optional: true
  belongs_to :employee, optional: true
  belongs_to :pos_token, optional: true

  validates :quantity_change, presence: true
  validates :reason, presence: true
end

