# 価格・税率の変更履歴。直前まで有効だった価格での会計（端末の同期待ち・オフライン会計）を
# 不正な価格変更と区別するために使う。store_id があれば店舗別価格、なければ商品マスタの価格。
class CreateProductPriceHistories < ActiveRecord::Migration[8.1]
  def change
    create_table :product_price_histories do |t|
      t.references :product, null: false, foreign_key: { on_delete: :cascade }
      t.references :store, foreign_key: { on_delete: :cascade }
      t.integer :price, null: false
      t.integer :tax_rate
      t.integer :tax_type
      t.datetime :replaced_at, null: false
      t.index [ :product_id, :replaced_at ]
    end
  end
end
