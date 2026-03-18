class CreateStockMovements < ActiveRecord::Migration[8.1]
  def change
    create_table :stock_movements do |t|
      t.references :store, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.references :store_stock, null: false, foreign_key: true
      t.references :sale, foreign_key: true
      t.references :employee, foreign_key: true
      t.references :pos_token, foreign_key: true

      t.integer :quantity_change, null: false
      t.string :reason, null: false

      t.timestamps
    end

    add_index :stock_movements, [:store_id, :product_id, :created_at], name: "index_stock_movements_on_store_product_created_at"
  end
end

