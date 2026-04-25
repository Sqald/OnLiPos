class CreateTableOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :table_orders do |t|
      t.references :store, null: false, foreign_key: true
      t.string :table_number, null: false
      t.jsonb :items, default: [], null: false
      t.timestamps
    end
    add_index :table_orders, %i[store_id table_number], unique: true
  end
end
