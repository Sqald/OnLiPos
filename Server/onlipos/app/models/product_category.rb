class ProductCategory < ApplicationRecord
  belongs_to :user
  has_many :products, foreign_key: :product_category_id, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :display_order, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
