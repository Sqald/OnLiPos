class CreateTransferOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :transfer_orders do |t|
      t.references :store, null: false, foreign_key: true
      t.string  :operator_name, null: false
      t.integer :operator_id,   null: false
      t.integer :total_amount,  null: false, default: 0
      t.string  :table_number             # 飲食店モード連携用（任意）
      t.jsonb   :items,         null: false, default: []
      t.timestamps
    end
  end
end
