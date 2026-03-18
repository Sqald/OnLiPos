class CreateStoreStocks < ActiveRecord::Migration[8.1]
  def change
    create_table :store_stocks do |t|
      t.references :store, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, default: 0, null: false

      t.timestamps
    end
    add_index :store_stocks, [:store_id, :product_id], unique: true
  end
end
