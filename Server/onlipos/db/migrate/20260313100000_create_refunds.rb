class CreateRefunds < ActiveRecord::Migration[8.1]
  def change
    create_table :refunds do |t|
      t.references :sale, null: false, foreign_key: true
      t.references :store, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :pos_token, null: true, foreign_key: true
      t.integer :total_amount, null: false, default: 0
      t.string :refund_receipt_number

      t.timestamps
    end

    add_index :refunds, :refund_receipt_number
    add_index :refunds, [:store_id, :created_at]

    create_table :refund_details do |t|
      t.references :refund, null: false, foreign_key: true
      t.references :saledetail, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.string :product_name, null: false
      t.integer :quantity, null: false
      t.integer :unit_price, null: false
      t.integer :subtotal, null: false

      t.timestamps
    end

    add_index :refund_details, [:refund_id, :saledetail_id]
  end
end
