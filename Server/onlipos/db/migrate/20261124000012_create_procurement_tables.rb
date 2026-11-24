# 仕入先・発注・入荷・棚卸
class CreateProcurementTables < ActiveRecord::Migration[8.1]
  def change
    create_table :suppliers do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :contact_name
      t.string :phone
      t.string :email
      t.string :invoice_registration_number
      t.text :note
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index [ :user_id, :name ], unique: true
    end
    add_reference :products, :supplier, foreign_key: { on_delete: :nullify }

    create_table :purchase_orders do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :store, null: false, foreign_key: true
      t.references :supplier, null: false, foreign_key: true
      t.string :number, null: false
      t.integer :status, null: false, default: 0
      t.date :ordered_on
      t.date :expected_on
      t.text :note
      t.timestamps
      t.index [ :user_id, :number ], unique: true
    end
    create_table :purchase_order_items do |t|
      t.references :purchase_order, null: false, foreign_key: { on_delete: :cascade }
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false
      t.integer :received_quantity, null: false, default: 0
      t.integer :unit_cost, null: false, default: 0
      t.timestamps
      t.index [ :purchase_order_id, :product_id ], unique: true
      t.check_constraint "quantity > 0 AND received_quantity >= 0", name: "purchase_order_items_quantities"
    end

    create_table :stocktakes do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :store, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :status, null: false, default: 0
      t.datetime :completed_at
      t.string :completed_by_name
      t.timestamps
    end
    create_table :stocktake_items do |t|
      t.references :stocktake, null: false, foreign_key: { on_delete: :cascade }
      t.references :product, null: false, foreign_key: true
      t.integer :counted_quantity, null: false
      t.integer :expected_quantity
      t.references :employee, foreign_key: true
      t.timestamps
      t.index [ :stocktake_id, :product_id ], unique: true
    end
  end
end
