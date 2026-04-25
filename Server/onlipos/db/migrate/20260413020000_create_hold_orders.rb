class CreateHoldOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :hold_orders do |t|
      t.references :store, null: false, foreign_key: true
      t.string :operator_name, null: false
      t.integer :operator_id, null: false
      t.integer :total_amount, null: false, default: 0
      t.jsonb :items, default: [], null: false
      t.timestamps
    end
  end
end
