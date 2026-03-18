class Price < ApplicationRecord
  belongs_to :store
  belongs_to :product

  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
