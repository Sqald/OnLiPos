class CreateStores < ActiveRecord::Migration[8.1]
  def change
    create_table :stores do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null:false
      t.string :ascii_name, null:false
      t.string :address
      t.string :phone_number
      t.text :description

      t.timestamps
    end
  end
end
