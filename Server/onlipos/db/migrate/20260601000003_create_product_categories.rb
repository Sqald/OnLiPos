class CreateProductCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :product_categories do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :name,          null: false
      t.integer :display_order, null: false, default: 0
      t.timestamps
    end

    add_index :product_categories, [ :user_id, :name ], unique: true

    add_reference :products, :product_category, null: true, foreign_key: true
  end
end
