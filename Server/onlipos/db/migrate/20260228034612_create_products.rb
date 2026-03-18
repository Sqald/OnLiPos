class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.references :user, null: false, foreign_key: true
      t.string :code, null: false
      t.string :name, null: false
      t.integer :price, default: 0, null: false
      t.text :description
      t.integer :status, default: 0, null: false

      t.timestamps
    end
    add_index :products, [:user_id, :code], unique: true
  end
end
