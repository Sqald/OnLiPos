# 会員・ポイント・クーポン・自動値引き
class CreateMarketingTables < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :code, null: false
      t.string :name
      t.string :phone
      t.string :email
      t.date :birthday
      t.text :note
      t.integer :points, null: false, default: 0
      t.integer :receivable, null: false, default: 0
      t.boolean :credit_allowed, null: false, default: false
      t.integer :visits_count, null: false, default: 0
      t.datetime :last_visited_at
      t.datetime :anonymized_at
      t.timestamps
      t.index [ :user_id, :code ], unique: true
      t.index [ :user_id, :phone ]
      t.check_constraint "points >= 0", name: "customers_points_non_negative"
    end

    create_table :point_transactions do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :sale, foreign_key: true
      t.references :refund, foreign_key: true
      t.integer :kind, null: false
      t.integer :points, null: false
      t.integer :balance, null: false
      t.string :note
      t.datetime :created_at, null: false
    end

    # 掛売の増減（会計・返品・入金）
    create_table :receivable_transactions do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :sale, foreign_key: true
      t.references :refund, foreign_key: true
      t.integer :amount, null: false
      t.integer :balance, null: false
      t.string :note
      t.datetime :created_at, null: false
    end

    create_table :coupons do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :code, null: false
      t.string :name, null: false
      t.integer :discount_type, null: false, default: 0
      t.integer :discount_value, null: false
      t.integer :min_total, null: false, default: 0
      t.date :starts_on
      t.date :ends_on
      t.integer :usage_limit
      t.integer :used_count, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index [ :user_id, :code ], unique: true
    end

    create_table :promotions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.integer :kind, null: false
      t.references :product_category, foreign_key: { on_delete: :cascade }
      t.integer :percent_off
      t.integer :fixed_price
      t.integer :set_quantity
      t.date :starts_on
      t.date :ends_on
      t.integer :start_minute
      t.integer :end_minute
      t.integer :weekdays, array: true, null: false, default: []
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    create_join_table :products, :promotions do |t|
      t.index [ :promotion_id, :product_id ], unique: true
      t.index :product_id
    end
    add_foreign_key :products_promotions, :products, on_delete: :cascade
    add_foreign_key :products_promotions, :promotions, on_delete: :cascade

    change_table :users, bulk: true do |t|
      t.integer :point_yen_per_point, null: false, default: 0
      t.string :receipt_footer
      t.boolean :digital_receipt_enabled, null: false, default: true
    end

    change_table :sales, bulk: true do |t|
      t.references :customer, foreign_key: true
      t.references :coupon, foreign_key: true
      t.integer :points_earned, null: false, default: 0
      t.integer :promotion_discount_total, null: false, default: 0
      t.string :public_token
    end
    add_index :sales, :public_token, unique: true

    change_table :sale_payments, bulk: true do |t|
      t.string :external_reference
      t.string :terminal_provider
    end
  end
end
