class CreateCashLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :cash_logs do |t|
      t.references :pos_token, null: false, foreign_key: true
      t.references :employee, null: false, foreign_key: true
      t.date :open_date, null: false
      t.boolean :is_start, default: false, null: false
      t.boolean :is_end, default: false, null: false
      t.integer :yen_10000, default: 0, null: false
      t.integer :yen_5000, default: 0, null: false
      t.integer :yen_1000, default: 0, null: false
      t.integer :yen_500, default: 0, null: false
      t.integer :yen_100, default: 0, null: false 
      t.integer :yen_50, default: 0, null: false
      t.integer :yen_10, default: 0, null: false
      t.integer :yen_5, default: 0, null: false
      t.integer :yen_1, default: 0, null: false

      t.timestamps
    end
  end
end
