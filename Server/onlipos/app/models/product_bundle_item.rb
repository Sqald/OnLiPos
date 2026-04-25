class ProductBundleItem < ApplicationRecord
  belongs_to :product_bundle
  belongs_to :product

  validates :quantity, numericality: { greater_than: 0 }
end
