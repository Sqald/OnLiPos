# 勤怠・予約・セルフ注文・キッチン・客用表示・外部連携
class CreateOperationsTables < ActiveRecord::Migration[8.1]
  def change
    create_table :attendances do |t|
      t.references :employee, null: false, foreign_key: true
      t.references :store, null: false, foreign_key: true
      t.references :pos_token, foreign_key: { on_delete: :nullify }
      t.datetime :clock_in_at, null: false
      t.datetime :clock_out_at
      t.integer :break_minutes, null: false, default: 0
      t.datetime :break_started_at
      t.string :corrected_by_name
      t.timestamps
      t.index :employee_id, unique: true, where: "clock_out_at IS NULL", name: "index_attendances_open_per_employee"
      t.index [ :store_id, :clock_in_at ]
    end

    create_table :reservations do |t|
      t.references :store, null: false, foreign_key: { on_delete: :cascade }
      t.references :customer, foreign_key: { on_delete: :nullify }
      t.string :name, null: false
      t.string :phone
      t.integer :party_size, null: false, default: 1
      t.string :table_number
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.integer :status, null: false, default: 0
      t.text :note
      t.timestamps
      t.index [ :store_id, :starts_at ]
    end

    # 卓ごとのQRコード（セルフ注文の入口）
    create_table :table_codes do |t|
      t.references :store, null: false, foreign_key: { on_delete: :cascade }
      t.string :table_number, null: false
      t.string :token, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index :token, unique: true
      t.index [ :store_id, :table_number ], unique: true
    end

    # 厨房への注文（セルフ注文・レジからの注文）
    create_table :kitchen_orders do |t|
      t.references :store, null: false, foreign_key: { on_delete: :cascade }
      t.string :table_number
      t.integer :source, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.jsonb :items, null: false, default: []
      t.string :client_request_id
      t.datetime :accepted_at
      t.datetime :served_at
      t.timestamps
      t.index [ :store_id, :status, :created_at ]
      t.index [ :store_id, :client_request_id ], unique: true, where: "client_request_id IS NOT NULL"
    end

    # 客用表示（カートの内容をブラウザの別画面に表示する）
    create_table :customer_displays do |t|
      t.references :pos_token, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :token, null: false
      t.jsonb :content, null: false, default: {}
      t.timestamps
      t.index :token, unique: true
    end

    change_table :stores, bulk: true do |t|
      t.boolean :self_order_enabled, null: false, default: false
      t.string :kitchen_display_token
    end
    add_index :stores, :kitchen_display_token, unique: true

    create_table :api_keys do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :token_hint, null: false
      t.string :scopes, array: true, null: false, default: []
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
      t.index :token_digest, unique: true
    end

    create_table :webhooks do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :url, null: false
      t.text :secret_ciphertext, null: false
      t.string :events, array: true, null: false, default: []
      t.boolean :active, null: false, default: true
      t.integer :failure_count, null: false, default: 0
      t.datetime :last_delivered_at
      t.string :last_error
      t.timestamps
    end
  end
end
