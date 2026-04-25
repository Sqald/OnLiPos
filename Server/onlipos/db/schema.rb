# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_15_010000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "cash_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "employee_id", null: false
    t.boolean "is_end", default: false, null: false
    t.boolean "is_start", default: false, null: false
    t.date "open_date", null: false
    t.bigint "pos_token_id", null: false
    t.datetime "updated_at", null: false
    t.integer "yen_1", default: 0, null: false
    t.integer "yen_10", default: 0, null: false
    t.integer "yen_100", default: 0, null: false
    t.integer "yen_1000", default: 0, null: false
    t.integer "yen_10000", default: 0, null: false
    t.integer "yen_5", default: 0, null: false
    t.integer "yen_50", default: 0, null: false
    t.integer "yen_500", default: 0, null: false
    t.integer "yen_5000", default: 0, null: false
    t.index ["employee_id"], name: "index_cash_logs_on_employee_id"
    t.index ["pos_token_id"], name: "index_cash_logs_on_pos_token_id"
  end

  create_table "employees", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.boolean "is_all_stores", default: false, null: false
    t.datetime "locked_at"
    t.string "name"
    t.string "pin_digest"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "code"], name: "index_employees_on_user_id_and_code", unique: true
    t.index ["user_id"], name: "index_employees_on_user_id"
  end

  create_table "employees_stores", id: false, force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.bigint "store_id", null: false
    t.index ["employee_id", "store_id"], name: "index_employees_stores_on_employee_id_and_store_id"
    t.index ["store_id", "employee_id"], name: "index_employees_stores_on_store_id_and_employee_id"
  end

  create_table "hold_orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "items", default: [], null: false
    t.integer "operator_id", null: false
    t.string "operator_name", null: false
    t.bigint "store_id", null: false
    t.integer "total_amount", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["store_id"], name: "index_hold_orders_on_store_id"
  end

  create_table "pos_tokens", force: :cascade do |t|
    t.string "ascii_name"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "name"
    t.bigint "next_receipt_sequence", default: 1, null: false
    t.string "password_digest"
    t.bigint "provisioning_id"
    t.bigint "store_id", null: false
    t.string "token"
    t.datetime "updated_at", null: false
    t.index ["provisioning_id"], name: "index_pos_tokens_on_provisioning_id"
    t.index ["store_id"], name: "index_pos_tokens_on_store_id"
    t.index ["token"], name: "index_pos_tokens_on_token", unique: true
  end

  create_table "prices", force: :cascade do |t|
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.bigint "store_id", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_prices_on_product_id"
    t.index ["store_id", "product_id"], name: "index_prices_on_store_id_and_product_id", unique: true
    t.index ["store_id"], name: "index_prices_on_store_id"
  end

  create_table "product_bundle_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_bundle_id", null: false
    t.bigint "product_id", null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["product_bundle_id", "product_id"], name: "index_product_bundle_items_on_product_bundle_id_and_product_id", unique: true
    t.index ["product_bundle_id"], name: "index_product_bundle_items_on_product_bundle_id"
    t.index ["product_id"], name: "index_product_bundle_items_on_product_id"
  end

  create_table "product_bundles", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "price", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "code"], name: "index_product_bundles_on_user_id_and_code", unique: true
    t.index ["user_id"], name: "index_product_bundles_on_user_id"
  end

  create_table "products", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "price", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.integer "tax_rate", default: 10, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "code"], name: "index_products_on_user_id_and_code", unique: true
    t.index ["user_id"], name: "index_products_on_user_id"
  end

  create_table "provisionings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "hardware_settings", default: {}, null: false
    t.string "name", null: false
    t.jsonb "store_context", default: {}, null: false
    t.bigint "store_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["store_id"], name: "index_provisionings_on_store_id"
    t.index ["user_id"], name: "index_provisionings_on_user_id"
  end

  create_table "refund_details", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.string "product_name", null: false
    t.integer "quantity", null: false
    t.bigint "refund_id", null: false
    t.bigint "saledetail_id", null: false
    t.integer "subtotal", null: false
    t.integer "unit_price", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_refund_details_on_product_id"
    t.index ["refund_id", "saledetail_id"], name: "index_refund_details_on_refund_id_and_saledetail_id"
    t.index ["refund_id"], name: "index_refund_details_on_refund_id"
    t.index ["saledetail_id"], name: "index_refund_details_on_saledetail_id"
  end

  create_table "refunds", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "pos_token_id"
    t.string "refund_receipt_number"
    t.bigint "sale_id", null: false
    t.bigint "store_id", null: false
    t.integer "total_amount", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["pos_token_id"], name: "index_refunds_on_pos_token_id"
    t.index ["refund_receipt_number"], name: "index_refunds_on_refund_receipt_number"
    t.index ["sale_id"], name: "index_refunds_on_sale_id"
    t.index ["store_id", "created_at"], name: "index_refunds_on_store_id_and_created_at"
    t.index ["store_id"], name: "index_refunds_on_store_id"
    t.index ["user_id"], name: "index_refunds_on_user_id"
  end

  create_table "sale_payments", force: :cascade do |t|
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.integer "method", null: false
    t.bigint "sale_id", null: false
    t.datetime "updated_at", null: false
    t.index ["sale_id"], name: "index_sale_payments_on_sale_id"
  end

  create_table "saledetails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.string "product_name", null: false
    t.integer "quantity", default: 1, null: false
    t.bigint "sale_id", null: false
    t.integer "subtotal", null: false
    t.integer "tax_amount", default: 0, null: false
    t.integer "tax_rate", default: 0, null: false
    t.integer "unit_price", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_saledetails_on_product_id"
    t.index ["sale_id"], name: "index_saledetails_on_sale_id"
  end

  create_table "sales", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "payment_method", default: 0, null: false
    t.bigint "pos_token_id"
    t.string "receipt_number", null: false
    t.bigint "store_id", null: false
    t.integer "subtotal_ex_tax", default: 0, null: false
    t.integer "tax_amount", default: 0, null: false
    t.integer "total_amount", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["pos_token_id"], name: "index_sales_on_pos_token_id"
    t.index ["receipt_number"], name: "index_sales_on_receipt_number", unique: true
    t.index ["store_id"], name: "index_sales_on_store_id"
    t.index ["user_id"], name: "index_sales_on_user_id"
  end

  create_table "stock_movements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "employee_id"
    t.bigint "pos_token_id"
    t.bigint "product_id", null: false
    t.integer "quantity_change", null: false
    t.string "reason", null: false
    t.bigint "sale_id"
    t.bigint "store_id", null: false
    t.bigint "store_stock_id", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id"], name: "index_stock_movements_on_employee_id"
    t.index ["pos_token_id"], name: "index_stock_movements_on_pos_token_id"
    t.index ["product_id"], name: "index_stock_movements_on_product_id"
    t.index ["sale_id"], name: "index_stock_movements_on_sale_id"
    t.index ["store_id", "product_id", "created_at"], name: "index_stock_movements_on_store_product_created_at"
    t.index ["store_id"], name: "index_stock_movements_on_store_id"
    t.index ["store_stock_id"], name: "index_stock_movements_on_store_stock_id"
  end

  create_table "store_stocks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.integer "quantity", default: 0, null: false
    t.bigint "store_id", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_store_stocks_on_product_id"
    t.index ["store_id", "product_id"], name: "index_store_stocks_on_store_id_and_product_id", unique: true
    t.index ["store_id"], name: "index_store_stocks_on_store_id"
  end

  create_table "stores", force: :cascade do |t|
    t.string "address"
    t.string "ascii_name", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "phone_number"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_stores_on_user_id"
  end

  create_table "table_orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "items", default: [], null: false
    t.bigint "store_id", null: false
    t.string "table_number", null: false
    t.datetime "updated_at", null: false
    t.index ["store_id", "table_number"], name: "index_table_orders_on_store_id_and_table_number", unique: true
    t.index ["store_id"], name: "index_table_orders_on_store_id"
  end

  create_table "transfer_orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "items", default: [], null: false
    t.integer "operator_id", null: false
    t.string "operator_name", null: false
    t.bigint "store_id", null: false
    t.string "table_number"
    t.integer "total_amount", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["store_id"], name: "index_transfer_orders_on_store_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "company_name"
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "first_name"
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "locked_at"
    t.string "login_name", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.integer "user_type"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["login_name"], name: "index_users_on_login_name", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  add_foreign_key "hold_orders", "stores"
  add_foreign_key "table_orders", "stores"
  add_foreign_key "transfer_orders", "stores"
  add_foreign_key "cash_logs", "employees"
  add_foreign_key "cash_logs", "pos_tokens"
  add_foreign_key "employees", "users"
  add_foreign_key "pos_tokens", "provisionings"
  add_foreign_key "pos_tokens", "stores"
  add_foreign_key "prices", "products"
  add_foreign_key "prices", "stores"
  add_foreign_key "product_bundle_items", "product_bundles"
  add_foreign_key "product_bundle_items", "products"
  add_foreign_key "product_bundles", "users"
  add_foreign_key "products", "users"
  add_foreign_key "provisionings", "stores"
  add_foreign_key "provisionings", "users"
  add_foreign_key "refund_details", "products"
  add_foreign_key "refund_details", "refunds"
  add_foreign_key "refund_details", "saledetails"
  add_foreign_key "refunds", "pos_tokens"
  add_foreign_key "refunds", "sales"
  add_foreign_key "refunds", "stores"
  add_foreign_key "refunds", "users"
  add_foreign_key "sale_payments", "sales"
  add_foreign_key "saledetails", "products"
  add_foreign_key "saledetails", "sales"
  add_foreign_key "sales", "pos_tokens"
  add_foreign_key "sales", "stores"
  add_foreign_key "sales", "users"
  add_foreign_key "stock_movements", "employees"
  add_foreign_key "stock_movements", "pos_tokens"
  add_foreign_key "stock_movements", "products"
  add_foreign_key "stock_movements", "sales"
  add_foreign_key "stock_movements", "store_stocks"
  add_foreign_key "stock_movements", "stores"
  add_foreign_key "store_stocks", "products"
  add_foreign_key "store_stocks", "stores"
  add_foreign_key "stores", "users"
end
