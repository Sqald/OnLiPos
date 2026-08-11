# Sale の明細行（商品1品目ごとの数量・単価・税情報）。
# 命名は Rails の規約に沿わない不規則名（sale_details ではなく saledetails）である点に注意。
class Saledetail < ApplicationRecord
  belongs_to :sale
  belongs_to :product
  has_many :refund_details, dependent: :restrict_with_exception

  # 販売時点の税区分の凍結（商品マスタの変更に影響されない）
  enum :tax_type, { inclusive: 0, exclusive: 1, tax_free: 2 }, prefix: :tax
end
