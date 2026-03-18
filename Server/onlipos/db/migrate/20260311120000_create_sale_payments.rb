class CreateSalePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :sale_payments, if_not_exists: true do |t|
      t.references :sale, null: false, foreign_key: true
      t.integer :method, null: false
      t.integer :amount, null: false

      t.timestamps
    end

    # すでにインデックスが存在する環境でもエラーにならないようにガードする
    unless index_exists?(:sale_payments, :sale_id)
      add_index :sale_payments, :sale_id
    end
  end
end

