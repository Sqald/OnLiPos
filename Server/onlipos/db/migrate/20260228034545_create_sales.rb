class CreateSales < ActiveRecord::Migration[8.1]
  def change
    create_table :sales do |t|
      t.references :user, null: false, foreign_key: true
      t.references :store, null: false, foreign_key: true
      t.references :pos_token, null: true, foreign_key: true # POS端末情報（Web管理画面からの操作等を考慮しnull許容も検討可だが、基本は必須）
      t.integer :payment_method, null: false, default: 0
      t.integer :total_amount, null: false
      t.string :receipt_number, null: false


      t.timestamps
    end
    add_index :sales, :receipt_number, unique: true
  end
end
