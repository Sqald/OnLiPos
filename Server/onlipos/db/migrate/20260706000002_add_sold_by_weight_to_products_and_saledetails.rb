# 量り売り（計量）商品対応（寺岡精工の対面計量POS等に見られる、はかりで計量した重量から
# 単価（100gあたり）で会計金額を算出する方式）。
# sold_by_weight が true の商品は products.price を「100gあたりの単価」として扱い、
# 会計時に重量（g）を入力して金額を算出する。
class AddSoldByWeightToProductsAndSaledetails < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :sold_by_weight, :boolean, null: false, default: false
    add_column :saledetails, :weight_grams, :integer
  end
end
