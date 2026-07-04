# 税計算の設定を企業（users）・商品（products）・売上明細（saledetails）に追加する。
# - users.tax_rounding_method: 消費税の端数処理方式（0: 切捨て, 1: 四捨五入, 2: 切上げ）。
#   既定 0 は現行実装（floor）と同じ挙動。
# - users.invoice_registration_number: 適格請求書発行事業者の登録番号（T+13桁）。
# - products.tax_type / saledetails.tax_type: 内税/外税/非課税（0: 内税 = 現行挙動, 1: 外税, 2: 非課税）。
#   明細側にも持つのは、販売時点の税区分を商品マスタの変更から独立して保全するため。
class AddTaxSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :tax_rounding_method, :integer, null: false, default: 0
    add_column :users, :invoice_registration_number, :string

    add_column :products, :tax_type, :integer, null: false, default: 0
    add_column :saledetails, :tax_type, :integer, null: false, default: 0
  end
end
