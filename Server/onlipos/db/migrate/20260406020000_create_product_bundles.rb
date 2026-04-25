class CreateProductBundles < ActiveRecord::Migration[8.1]
  def change
    create_table :product_bundles do |t|
      t.bigint  :user_id,  null: false
      t.string  :code,     null: false
      t.string  :name,     null: false
      t.integer :price,    null: false, default: 0
      t.integer :status,   null: false, default: 0
      t.timestamps
    end
    add_index :product_bundles, [:user_id, :code], unique: true
    add_index :product_bundles, :user_id
    add_foreign_key :product_bundles, :users

    create_table :product_bundle_items do |t|
      t.bigint  :product_bundle_id, null: false
      t.bigint  :product_id,        null: false
      t.integer :quantity,          null: false, default: 1
      t.timestamps
    end
    add_index :product_bundle_items, [:product_bundle_id, :product_id], unique: true
    add_index :product_bundle_items, :product_bundle_id
    add_index :product_bundle_items, :product_id
    add_foreign_key :product_bundle_items, :product_bundles
    add_foreign_key :product_bundle_items, :products
  end
end
