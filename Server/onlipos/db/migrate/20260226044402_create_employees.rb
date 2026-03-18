class CreateEmployees < ActiveRecord::Migration[7.1]
  def change
    create_table :employees do |t|
      t.string :code, null: false
      t.string :name
      t.string :pin_digest
      t.boolean :is_all_stores, default: false, null: false
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
    add_index :employees, [:user_id, :code], unique: true
  end
end
