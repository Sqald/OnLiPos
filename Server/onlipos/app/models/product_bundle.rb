class ProductBundle < ApplicationRecord
  belongs_to :user
  has_many :product_bundle_items, dependent: :destroy
  has_many :products, through: :product_bundle_items

  enum :status, { active: 0, discontinued: 1 }

  validates :code, presence: true, uniqueness: { scope: :user_id }
  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }

  def status_i18n
    status == "active" ? "有効" : "廃盤"
  end
end
