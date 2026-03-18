class CreatePrices < ActiveRecord::Migration[8.1]
  def change
    create_table :prices do |t|
      t.references :store, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :amount, null: false

      t.timestamps
    end
    add_index :prices, [:store_id, :product_id], unique: true
  end
end
