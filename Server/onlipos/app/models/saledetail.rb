class Saledetail < ApplicationRecord
  belongs_to :sale
  belongs_to :product
  has_many :refund_details, dependent: :restrict_with_exception

  # 販売時点の税区分の凍結（商品マスタの変更に影響されない）
  enum :tax_type, { inclusive: 0, exclusive: 1, tax_free: 2 }, prefix: :tax
end
