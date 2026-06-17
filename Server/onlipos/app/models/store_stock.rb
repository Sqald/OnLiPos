class StoreStock < ApplicationRecord
  belongs_to :store
  belongs_to :product
  has_many :stock_movements, dependent: :destroy

  validates :quantity, numericality: { only_integer: true }
end
