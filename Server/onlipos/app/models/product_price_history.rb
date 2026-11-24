# 商品価格（store_id なし）・店舗別価格（store_id あり）の変更履歴。値は「変更前」のもの。
class ProductPriceHistory < ApplicationRecord
  belongs_to :product
  belongs_to :store, optional: true

  # 変更前の税率（店内飲食の指定がある場合はその税率）
  def tax_rate_for(eat_in) = (eat_in && eat_in_tax_rate) || tax_rate
end
