# 商品マスタの拡張（原価・店内飲食の税率/価格・年齢確認・在庫警告・バリエーション・オプション）、
# 税率/価格の予約変更、CSV取込の履歴
class ExtendCatalogAndTax < ActiveRecord::Migration[8.1]
  def change
    change_table :products, bulk: true do |t|
      t.integer :cost_price
      t.integer :eat_in_tax_rate
      t.integer :eat_in_price
      t.integer :min_age
      t.integer :low_stock_threshold
      t.string :variant_group
      t.string :variant_name
      t.boolean :track_stock, null: false, default: true
    end
    add_index :products, [ :user_id, :variant_group ], where: "variant_group IS NOT NULL"

    change_table :product_price_histories, bulk: true do |t|
      t.integer :eat_in_price
      t.integer :eat_in_tax_rate
    end

    change_table :saledetails, bulk: true do |t|
      t.integer :service_type, null: false, default: 0
      t.integer :cost_price
      t.jsonb :options, null: false, default: []
      t.string :promotion_name
    end

    add_column :sales, :age_verified, :boolean, null: false, default: false

    # 適用日を指定した価格・税率の変更。store_id があれば店舗別価格の変更
    create_table :scheduled_product_changes do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :product, null: false, foreign_key: { on_delete: :cascade }
      t.references :store, foreign_key: { on_delete: :cascade }
      t.date :effective_on, null: false
      t.integer :price
      t.integer :tax_rate
      t.integer :tax_type
      t.integer :eat_in_price
      t.integer :eat_in_tax_rate
      t.string :note
      t.string :batch
      t.datetime :applied_at
      t.timestamps
      t.index [ :user_id, :effective_on ], where: "applied_at IS NULL", name: "index_scheduled_changes_pending"
    end

    # トッピング・サイズなどのオプション
    create_table :option_groups do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.integer :min_select, null: false, default: 0
      t.integer :max_select, null: false, default: 1
      t.timestamps
      t.index [ :user_id, :name ], unique: true
    end
    create_table :option_items do |t|
      t.references :option_group, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.integer :price, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    create_join_table :products, :option_groups do |t|
      t.index [ :product_id, :option_group_id ], unique: true, name: "index_option_groups_products_unique"
      t.index :option_group_id
    end
    add_foreign_key :option_groups_products, :products, on_delete: :cascade
    add_foreign_key :option_groups_products, :option_groups, on_delete: :cascade

    create_table :product_imports do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :filename
      t.text :content
      t.integer :status, null: false, default: 0
      t.integer :imported_count, null: false, default: 0
      t.integer :updated_count, null: false, default: 0
      t.jsonb :error_messages, null: false, default: []
      t.datetime :finished_at
      t.timestamps
    end
  end
end
