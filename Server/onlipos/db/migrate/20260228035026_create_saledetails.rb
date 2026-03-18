class CreateSaledetails < ActiveRecord::Migration[8.1]
  def change
    create_table :saledetails do |t|
      t.references :sale, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.string :product_name, null: false
      t.integer :quantity, null: false, default: 1
      t.integer :unit_price, null: false
      t.integer :subtotal, null: false

      t.timestamps
    end
  end
end
