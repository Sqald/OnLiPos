class AddDiscountToSalesAndSaledetails < ActiveRecord::Migration[8.1]
  def change
    # 売上明細：割引前単価と割引額を記録する
    # original_unit_price: 価格変更前の定価（変更なければ NULL）
    # discount_amount: 値引き額（quantity × (original_unit_price - unit_price)）
    add_column :saledetails, :original_unit_price, :integer, null: true
    add_column :saledetails, :discount_amount, :integer, null: false, default: 0

    # 売上ヘッダー：明細の割引額合計を非正規化して保存
    add_column :sales, :total_discount, :integer, null: false, default: 0
  end
end
