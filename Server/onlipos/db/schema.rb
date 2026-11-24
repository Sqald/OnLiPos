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

ActiveRecord::Schema[8.1].define(version: 2026_11_24_000013) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "admin_id"
    t.datetime "created_at", null: false
    t.text "details"
    t.string "ip_address"
    t.bigint "target_id"
    t.string "target_type"
    t.index ["admin_id"], name: "index_admin_audit_logs_on_admin_id"
    t.index ["created_at"], name: "index_admin_audit_logs_on_created_at"
    t.index ["target_type", "target_id"], name: "index_admin_audit_logs_on_target_type_and_target_id"
  end

  create_table "admins", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "locked_at"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.text "otp_secret_ciphertext"
    t.datetime "otp_enabled_at"
    t.bigint "otp_last_used_timestep"
    t.integer "session_version", default: 0, null: false
    t.index ["username"], name: "index_admins_on_username", unique: true
  end

  create_table "api_keys", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "token_digest", null: false
    t.string "token_hint", null: false
    t.string "scopes", default: [], null: false, array: true
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_keys_on_user_id"
  end

  create_table "attendances", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.bigint "store_id", null: false
    t.bigint "pos_token_id"
    t.datetime "clock_in_at", null: false
    t.datetime "clock_out_at"
    t.integer "break_minutes", default: 0, null: false
    t.datetime "break_started_at"
    t.string "corrected_by_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id"], name: "index_attendances_on_employee_id"
    t.index ["employee_id"], name: "index_attendances_open_per_employee", unique: true, where: "(clock_out_at IS NULL)"
    t.index ["pos_token_id"], name: "index_attendances_on_pos_token_id"
    t.index ["store_id", "clock_in_at"], name: "index_attendances_on_store_id_and_clock_in_at"
    t.index ["store_id"], name: "index_attendances_on_store_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "actor_type"
    t.bigint "actor_id"
    t.string "actor_name"
    t.string "action", null: false
    t.string "target_type"
    t.bigint "target_id"
    t.string "target_name"
    t.jsonb "details", default: {}, null: false
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.index ["target_type", "target_id"], name: "index_audit_logs_on_target_type_and_target_id"
    t.index ["user_id", "created_at"], name: "index_audit_logs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "cash_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "diff_amount"
    t.bigint "employee_id", null: false
    t.integer "expected_amount"
    t.boolean "is_end", default: false, null: false
    t.boolean "is_pickup", default: false, null: false
    t.boolean "is_start", default: false, null: false
    t.integer "log_type", default: 1, null: false
    t.date "open_date", null: false
    t.integer "pickup_amount"
    t.string "pickup_reason"
    t.bigint "pos_token_id", null: false
    t.bigint "register_session_id"
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
    t.index ["pos_token_id", "open_date", "log_type"], name: "index_cash_logs_on_pos_token_id_and_open_date_and_log_type"
    t.index ["pos_token_id"], name: "index_cash_logs_on_pos_token_id"
    t.index ["register_session_id"], name: "index_cash_logs_on_register_session_id"
  end

  create_table "cash_movements", force: :cascade do |t|
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.integer "direction", null: false
    t.bigint "employee_id", null: false
    t.integer "kind", null: false
    t.datetime "occurred_at", null: false
    t.bigint "pos_token_id", null: false
    t.string "reason"
    t.bigint "register_session_id"
    t.bigint "store_id", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id"], name: "index_cash_movements_on_employee_id"
    t.index ["pos_token_id", "occurred_at"], name: "index_cash_movements_on_pos_token_id_and_occurred_at"
    t.index ["pos_token_id"], name: "index_cash_movements_on_pos_token_id"
    t.index ["register_session_id"], name: "index_cash_movements_on_register_session_id"
    t.index ["store_id", "occurred_at"], name: "index_cash_movements_on_store_id_and_occurred_at"
    t.index ["store_id"], name: "index_cash_movements_on_store_id"
    t.check_constraint "amount > 0", name: "cash_movements_amount_positive"
  end

  create_table "coupons", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "code", null: false
    t.string "name", null: false
    t.integer "discount_type", default: 0, null: false
    t.integer "discount_value", null: false
    t.integer "min_total", default: 0, null: false
    t.date "starts_on"
    t.date "ends_on"
    t.integer "usage_limit"
    t.integer "used_count", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "code"], name: "index_coupons_on_user_id_and_code", unique: true
    t.index ["user_id"], name: "index_coupons_on_user_id"
  end

  create_table "customer_displays", force: :cascade do |t|
    t.bigint "pos_token_id", null: false
    t.string "token", null: false
    t.jsonb "content", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pos_token_id"], name: "index_customer_displays_on_pos_token_id", unique: true
    t.index ["token"], name: "index_customer_displays_on_token", unique: true
  end

  create_table "customers", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "code", null: false
    t.string "name"
    t.string "phone"
    t.string "email"
    t.date "birthday"
    t.text "note"
    t.integer "points", default: 0, null: false
    t.integer "receivable", default: 0, null: false
    t.boolean "credit_allowed", default: false, null: false
    t.integer "visits_count", default: 0, null: false
    t.datetime "last_visited_at"
    t.datetime "anonymized_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "code"], name: "index_customers_on_user_id_and_code", unique: true
    t.index ["user_id", "phone"], name: "index_customers_on_user_id_and_phone"
    t.index ["user_id"], name: "index_customers_on_user_id"
    t.check_constraint "points >= 0", name: "customers_points_non_negative"
  end

  create_table "employee_permissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "employee_id", null: false
    t.string "permission", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id", "permission"], name: "index_employee_permissions_on_employee_id_and_permission", unique: true
    t.index ["employee_id"], name: "index_employee_permissions_on_employee_id"
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

  create_table "journal_anchors", force: :cascade do |t|
    t.bigint "pos_token_id", null: false
    t.bigint "sequence_number", null: false
    t.string "entry_hash", null: false
    t.string "signature", null: false
    t.datetime "created_at", null: false
    t.index ["pos_token_id", "sequence_number"], name: "index_journal_anchors_on_pos_token_id_and_sequence_number"
    t.index ["pos_token_id"], name: "index_journal_anchors_on_pos_token_id"
  end

  create_table "journal_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "employee_id"
    t.string "entry_hash"
    t.integer "entry_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.bigint "pos_token_id", null: false
    t.string "previous_hash"
    t.datetime "printed_at", null: false
    t.string "receipt_number"
    t.bigint "sequence_number"
    t.bigint "store_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["employee_id"], name: "index_journal_entries_on_employee_id"
    t.index ["pos_token_id", "printed_at"], name: "index_journal_entries_on_pos_token_id_and_printed_at"
    t.index ["pos_token_id", "sequence_number"], name: "index_journal_entries_on_pos_sequence", unique: true, where: "(sequence_number IS NOT NULL)"
    t.index ["pos_token_id"], name: "index_journal_entries_on_pos_token_id"
    t.index ["store_id", "printed_at"], name: "index_journal_entries_on_store_id_and_printed_at"
    t.index ["store_id"], name: "index_journal_entries_on_store_id"
    t.index ["user_id"], name: "index_journal_entries_on_user_id"
  end

  create_table "kitchen_orders", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.string "table_number"
    t.integer "source", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.jsonb "items", default: [], null: false
    t.string "client_request_id"
    t.datetime "accepted_at"
    t.datetime "served_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["store_id", "client_request_id"], name: "index_kitchen_orders_on_store_id_and_client_request_id", unique: true, where: "(client_request_id IS NOT NULL)"
    t.index ["store_id", "status", "created_at"], name: "index_kitchen_orders_on_store_id_and_status_and_created_at"
    t.index ["store_id"], name: "index_kitchen_orders_on_store_id"
  end

  create_table "operator_approvals", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.bigint "pos_token_id", null: false
    t.string "permission"
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.string "used_for"
    t.datetime "created_at", null: false
    t.index ["employee_id"], name: "index_operator_approvals_on_employee_id"
    t.index ["expires_at"], name: "index_operator_approvals_on_expires_at"
    t.index ["pos_token_id"], name: "index_operator_approvals_on_pos_token_id"
    t.index ["token_digest"], name: "index_operator_approvals_on_token_digest", unique: true
  end

  create_table "option_groups", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.integer "min_select", default: 0, null: false
    t.integer "max_select", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "name"], name: "index_option_groups_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_option_groups_on_user_id"
  end

  create_table "option_groups_products", id: false, force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "option_group_id", null: false
    t.index ["option_group_id"], name: "index_option_groups_products_on_option_group_id"
    t.index ["product_id", "option_group_id"], name: "index_option_groups_products_unique", unique: true
  end

  create_table "option_items", force: :cascade do |t|
    t.bigint "option_group_id", null: false
    t.string "name", null: false
    t.integer "price", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["option_group_id"], name: "index_option_items_on_option_group_id"
  end

  create_table "point_transactions", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.bigint "sale_id"
    t.bigint "refund_id"
    t.integer "kind", null: false
    t.integer "points", null: false
    t.integer "balance", null: false
    t.string "note"
    t.datetime "created_at", null: false
    t.index ["customer_id"], name: "index_point_transactions_on_customer_id"
    t.index ["refund_id"], name: "index_point_transactions_on_refund_id"
    t.index ["sale_id"], name: "index_point_transactions_on_sale_id"
  end

  create_table "pos_tokens", force: :cascade do |t|
    t.string "ascii_name"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "name"
    t.bigint "next_journal_sequence", default: 1, null: false
    t.bigint "next_receipt_sequence", default: 1, null: false
    t.string "password_digest"
    t.datetime "password_expires_at"
    t.bigint "provisioning_id"
    t.bigint "store_id", null: false
    t.datetime "updated_at", null: false
    t.string "token_digest"
    t.datetime "disabled_at"
    t.string "disabled_reason"
    t.string "app_version"
    t.string "platform"
    t.string "last_ip"
    t.index ["provisioning_id"], name: "index_pos_tokens_on_provisioning_id"
    t.index ["store_id"], name: "index_pos_tokens_on_store_id"
    t.index ["token_digest"], name: "index_pos_tokens_on_token_digest", unique: true
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

  create_table "product_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "display_order", default: 0, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "name"], name: "index_product_categories_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_product_categories_on_user_id"
  end

  create_table "product_imports", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "filename"
    t.text "content"
    t.integer "status", default: 0, null: false
    t.integer "imported_count", default: 0, null: false
    t.integer "updated_count", default: 0, null: false
    t.jsonb "error_messages", default: [], null: false
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_product_imports_on_user_id"
  end

  create_table "product_price_histories", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "store_id"
    t.integer "price", null: false
    t.integer "tax_rate"
    t.integer "tax_type"
    t.datetime "replaced_at", null: false
    t.integer "eat_in_price"
    t.integer "eat_in_tax_rate"
    t.index ["product_id", "replaced_at"], name: "index_product_price_histories_on_product_id_and_replaced_at"
    t.index ["product_id"], name: "index_product_price_histories_on_product_id"
    t.index ["store_id"], name: "index_product_price_histories_on_store_id"
  end

  create_table "products", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "price", default: 0, null: false
    t.bigint "product_category_id"
    t.boolean "sold_by_weight", default: false, null: false
    t.integer "status", default: 0, null: false
    t.integer "tax_rate", default: 10, null: false
    t.integer "tax_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "cost_price"
    t.integer "eat_in_tax_rate"
    t.integer "eat_in_price"
    t.integer "min_age"
    t.integer "low_stock_threshold"
    t.string "variant_group"
    t.string "variant_name"
    t.boolean "track_stock", default: true, null: false
    t.bigint "supplier_id"
    t.index ["product_category_id"], name: "index_products_on_product_category_id"
    t.index ["supplier_id"], name: "index_products_on_supplier_id"
    t.index ["user_id", "code"], name: "index_products_on_user_id_and_code", unique: true
    t.index ["user_id", "variant_group"], name: "index_products_on_user_id_and_variant_group", where: "(variant_group IS NOT NULL)"
    t.index ["user_id"], name: "index_products_on_user_id"
  end

  create_table "products_promotions", id: false, force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "promotion_id", null: false
    t.index ["product_id"], name: "index_products_promotions_on_product_id"
    t.index ["promotion_id", "product_id"], name: "index_products_promotions_on_promotion_id_and_product_id", unique: true
  end

  create_table "promotions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.integer "kind", null: false
    t.bigint "product_category_id"
    t.integer "percent_off"
    t.integer "fixed_price"
    t.integer "set_quantity"
    t.date "starts_on"
    t.date "ends_on"
    t.integer "start_minute"
    t.integer "end_minute"
    t.integer "weekdays", default: [], null: false, array: true
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_category_id"], name: "index_promotions_on_product_category_id"
    t.index ["user_id"], name: "index_promotions_on_user_id"
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

  create_table "purchase_order_items", force: :cascade do |t|
    t.bigint "purchase_order_id", null: false
    t.bigint "product_id", null: false
    t.integer "quantity", null: false
    t.integer "received_quantity", default: 0, null: false
    t.integer "unit_cost", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_purchase_order_items_on_product_id"
    t.index ["purchase_order_id", "product_id"], name: "index_purchase_order_items_on_purchase_order_id_and_product_id", unique: true
    t.index ["purchase_order_id"], name: "index_purchase_order_items_on_purchase_order_id"
    t.check_constraint "quantity > 0 AND received_quantity >= 0", name: "purchase_order_items_quantities"
  end

  create_table "purchase_orders", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "store_id", null: false
    t.bigint "supplier_id", null: false
    t.string "number", null: false
    t.integer "status", default: 0, null: false
    t.date "ordered_on"
    t.date "expected_on"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["store_id"], name: "index_purchase_orders_on_store_id"
    t.index ["supplier_id"], name: "index_purchase_orders_on_supplier_id"
    t.index ["user_id", "number"], name: "index_purchase_orders_on_user_id_and_number", unique: true
    t.index ["user_id"], name: "index_purchase_orders_on_user_id"
  end

  create_table "receivable_transactions", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.bigint "sale_id"
    t.bigint "refund_id"
    t.integer "amount", null: false
    t.integer "balance", null: false
    t.string "note"
    t.datetime "created_at", null: false
    t.index ["customer_id"], name: "index_receivable_transactions_on_customer_id"
    t.index ["refund_id"], name: "index_receivable_transactions_on_refund_id"
    t.index ["sale_id"], name: "index_receivable_transactions_on_sale_id"
  end

  create_table "refund_details", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.string "product_name", null: false
    t.integer "quantity", null: false
    t.bigint "refund_id", null: false
    t.bigint "saledetail_id", null: false
    t.integer "subtotal", null: false
    t.integer "tax_amount", default: 0, null: false
    t.integer "tax_rate", default: 0, null: false
    t.integer "unit_price", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_refund_details_on_product_id"
    t.index ["refund_id", "saledetail_id"], name: "index_refund_details_on_refund_id_and_saledetail_id"
    t.index ["refund_id"], name: "index_refund_details_on_refund_id"
    t.index ["saledetail_id"], name: "index_refund_details_on_saledetail_id"
  end

  create_table "refund_payments", force: :cascade do |t|
    t.bigint "refund_id", null: false
    t.integer "method", null: false
    t.integer "amount", null: false
    t.string "label"
    t.string "external_reference"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["refund_id"], name: "index_refund_payments_on_refund_id"
    t.check_constraint "amount > 0", name: "refund_payments_amount_positive"
  end

  create_table "refund_tax_breakdowns", force: :cascade do |t|
    t.integer "amount_ex_tax", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "refund_id", null: false
    t.integer "tax_amount", default: 0, null: false
    t.integer "tax_rate", null: false
    t.integer "tax_type", default: 0, null: false
    t.integer "taxable_amount", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["refund_id", "tax_rate", "tax_type"], name: "index_refund_tax_breakdowns_uniqueness", unique: true
    t.index ["refund_id"], name: "index_refund_tax_breakdowns_on_refund_id"
    t.check_constraint "taxable_amount >= 0 AND amount_ex_tax >= 0 AND tax_amount >= 0", name: "refund_tax_breakdowns_amounts_non_negative"
  end

  create_table "refunds", force: :cascade do |t|
    t.date "business_date"
    t.datetime "created_at", null: false
    t.bigint "employee_id"
    t.bigint "pos_token_id"
    t.string "refund_receipt_number"
    t.datetime "refunded_at"
    t.bigint "register_session_id"
    t.bigint "sale_id", null: false
    t.bigint "store_id", null: false
    t.integer "subtotal_ex_tax", default: 0, null: false
    t.integer "tax_amount", default: 0, null: false
    t.integer "total_amount", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["employee_id"], name: "index_refunds_on_employee_id"
    t.index ["pos_token_id"], name: "index_refunds_on_pos_token_id"
    t.index ["refund_receipt_number"], name: "index_refunds_on_refund_receipt_number"
    t.index ["register_session_id"], name: "index_refunds_on_register_session_id"
    t.index ["sale_id"], name: "index_refunds_on_sale_id"
    t.index ["store_id", "business_date"], name: "index_refunds_on_store_id_and_business_date"
    t.index ["store_id", "created_at"], name: "index_refunds_on_store_id_and_created_at"
    t.index ["store_id"], name: "index_refunds_on_store_id"
    t.index ["user_id"], name: "index_refunds_on_user_id"
  end

  create_table "register_sessions", force: :cascade do |t|
    t.date "business_date", null: false
    t.integer "cash_diff_amount"
    t.integer "cash_in_total"
    t.integer "cash_out_total"
    t.integer "cash_refund_total"
    t.integer "cash_sales_total"
    t.datetime "closed_at"
    t.integer "closing_counted_amount"
    t.bigint "closing_employee_id"
    t.jsonb "closing_summary", default: {}, null: false
    t.datetime "created_at", null: false
    t.integer "discount_total"
    t.integer "expected_cash_amount"
    t.integer "next_opening_float"
    t.datetime "opened_at", null: false
    t.bigint "opening_employee_id"
    t.integer "opening_float", default: 0, null: false
    t.bigint "pos_token_id", null: false
    t.integer "refund_count"
    t.integer "refund_total"
    t.integer "sales_count"
    t.integer "sales_total"
    t.integer "status", default: 0, null: false
    t.bigint "store_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "void_count"
    t.integer "void_total"
    t.bigint "z_number", null: false
    t.index ["closing_employee_id"], name: "index_register_sessions_on_closing_employee_id"
    t.index ["opening_employee_id"], name: "index_register_sessions_on_opening_employee_id"
    t.index ["pos_token_id", "z_number"], name: "index_register_sessions_on_pos_token_id_and_z_number", unique: true
    t.index ["pos_token_id"], name: "index_register_sessions_on_pos_token_id"
    t.index ["pos_token_id"], name: "index_register_sessions_open_per_pos", unique: true, where: "(status = 0)"
    t.index ["store_id", "business_date"], name: "index_register_sessions_on_store_id_and_business_date"
    t.index ["store_id"], name: "index_register_sessions_on_store_id"
    t.index ["user_id"], name: "index_register_sessions_on_user_id"
    t.check_constraint "opening_float >= 0", name: "register_sessions_opening_float_non_negative"
  end

  create_table "reservations", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.bigint "customer_id"
    t.string "name", null: false
    t.string "phone"
    t.integer "party_size", default: 1, null: false
    t.string "table_number"
    t.datetime "starts_at", null: false
    t.datetime "ends_at"
    t.integer "status", default: 0, null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_reservations_on_customer_id"
    t.index ["store_id", "starts_at"], name: "index_reservations_on_store_id_and_starts_at"
    t.index ["store_id"], name: "index_reservations_on_store_id"
  end

  create_table "sale_payments", force: :cascade do |t|
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.string "label"
    t.integer "method", null: false
    t.bigint "sale_id", null: false
    t.datetime "updated_at", null: false
    t.string "external_reference"
    t.string "terminal_provider"
    t.index ["sale_id"], name: "index_sale_payments_on_sale_id"
  end

  create_table "sale_tax_breakdowns", force: :cascade do |t|
    t.integer "amount_ex_tax", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "sale_id", null: false
    t.integer "tax_amount", default: 0, null: false
    t.integer "tax_rate", null: false
    t.integer "tax_type", default: 0, null: false
    t.integer "taxable_amount", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["sale_id", "tax_rate", "tax_type"], name: "index_sale_tax_breakdowns_uniqueness", unique: true
    t.index ["sale_id"], name: "index_sale_tax_breakdowns_on_sale_id"
    t.check_constraint "taxable_amount >= 0 AND amount_ex_tax >= 0 AND tax_amount >= 0", name: "sale_tax_breakdowns_amounts_non_negative"
  end

  create_table "saledetails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "discount_amount", default: 0, null: false
    t.string "discount_reason"
    t.integer "original_unit_price"
    t.bigint "product_id", null: false
    t.string "product_name", null: false
    t.integer "quantity", default: 1, null: false
    t.bigint "sale_id", null: false
    t.integer "subtotal", null: false
    t.integer "tax_amount", default: 0, null: false
    t.integer "tax_rate", default: 0, null: false
    t.integer "tax_type", default: 0, null: false
    t.integer "unit_price", null: false
    t.datetime "updated_at", null: false
    t.integer "weight_grams"
    t.integer "service_type", default: 0, null: false
    t.integer "cost_price"
    t.jsonb "options", default: [], null: false
    t.string "promotion_name"
    t.index ["product_id"], name: "index_saledetails_on_product_id"
    t.index ["sale_id"], name: "index_saledetails_on_sale_id"
  end

  create_table "sales", force: :cascade do |t|
    t.date "business_date"
    t.string "client_request_id"
    t.datetime "created_at", null: false
    t.integer "customer_age_group"
    t.integer "customer_gender"
    t.bigint "employee_id"
    t.string "order_discount_reason"
    t.integer "order_discount_total", default: 0, null: false
    t.integer "order_discount_type"
    t.integer "order_discount_value"
    t.integer "payment_method", default: 0, null: false
    t.bigint "pos_token_id"
    t.string "receipt_number", null: false
    t.bigint "register_session_id"
    t.datetime "sold_at"
    t.integer "status", default: 0, null: false
    t.bigint "store_id", null: false
    t.integer "subtotal_ex_tax", default: 0, null: false
    t.integer "tax_amount", default: 0, null: false
    t.integer "total_amount", null: false
    t.integer "total_discount", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "void_reason"
    t.datetime "voided_at"
    t.bigint "voided_by_employee_id"
    t.jsonb "review_reasons", default: [], null: false
    t.datetime "reviewed_at"
    t.string "reviewed_by_name"
    t.boolean "offline", default: false, null: false
    t.bigint "discount_approver_id"
    t.boolean "age_verified", default: false, null: false
    t.bigint "customer_id"
    t.bigint "coupon_id"
    t.integer "points_earned", default: 0, null: false
    t.integer "promotion_discount_total", default: 0, null: false
    t.string "public_token"
    t.index ["coupon_id"], name: "index_sales_on_coupon_id"
    t.index ["customer_id"], name: "index_sales_on_customer_id"
    t.index ["discount_approver_id"], name: "index_sales_on_discount_approver_id"
    t.index ["employee_id"], name: "index_sales_on_employee_id"
    t.index ["pos_token_id", "client_request_id"], name: "index_sales_on_pos_token_id_and_client_request_id", unique: true, where: "(client_request_id IS NOT NULL)"
    t.index ["pos_token_id"], name: "index_sales_on_pos_token_id"
    t.index ["public_token"], name: "index_sales_on_public_token", unique: true
    t.index ["receipt_number"], name: "index_sales_on_receipt_number", unique: true
    t.index ["register_session_id"], name: "index_sales_on_register_session_id"
    t.index ["store_id", "business_date"], name: "index_sales_on_store_id_and_business_date"
    t.index ["store_id"], name: "index_sales_on_store_id"
    t.index ["user_id", "reviewed_at"], name: "index_sales_needing_review", where: "(review_reasons <> '[]'::jsonb)"
    t.index ["user_id"], name: "index_sales_on_user_id"
    t.index ["voided_by_employee_id"], name: "index_sales_on_voided_by_employee_id"
  end

  create_table "scheduled_product_changes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "product_id", null: false
    t.bigint "store_id"
    t.date "effective_on", null: false
    t.integer "price"
    t.integer "tax_rate"
    t.integer "tax_type"
    t.integer "eat_in_price"
    t.integer "eat_in_tax_rate"
    t.string "note"
    t.string "batch"
    t.datetime "applied_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_scheduled_product_changes_on_product_id"
    t.index ["store_id"], name: "index_scheduled_product_changes_on_store_id"
    t.index ["user_id", "effective_on"], name: "index_scheduled_changes_pending", where: "(applied_at IS NULL)"
    t.index ["user_id"], name: "index_scheduled_product_changes_on_user_id"
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

  create_table "stocktake_items", force: :cascade do |t|
    t.bigint "stocktake_id", null: false
    t.bigint "product_id", null: false
    t.integer "counted_quantity", null: false
    t.integer "expected_quantity"
    t.bigint "employee_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id"], name: "index_stocktake_items_on_employee_id"
    t.index ["product_id"], name: "index_stocktake_items_on_product_id"
    t.index ["stocktake_id", "product_id"], name: "index_stocktake_items_on_stocktake_id_and_product_id", unique: true
    t.index ["stocktake_id"], name: "index_stocktake_items_on_stocktake_id"
  end

  create_table "stocktakes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "store_id", null: false
    t.string "name", null: false
    t.integer "status", default: 0, null: false
    t.datetime "completed_at"
    t.string "completed_by_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["store_id"], name: "index_stocktakes_on_store_id"
    t.index ["user_id"], name: "index_stocktakes_on_user_id"
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
    t.boolean "self_order_enabled", default: false, null: false
    t.string "kitchen_display_token"
    t.index ["kitchen_display_token"], name: "index_stores_on_kitchen_display_token", unique: true
    t.index ["user_id"], name: "index_stores_on_user_id"
  end

  create_table "suppliers", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "contact_name"
    t.string "phone"
    t.string "email"
    t.string "invoice_registration_number"
    t.text "note"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "name"], name: "index_suppliers_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_suppliers_on_user_id"
  end

  create_table "table_codes", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.string "table_number", null: false
    t.string "token", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["store_id", "table_number"], name: "index_table_codes_on_store_id_and_table_number", unique: true
    t.index ["store_id"], name: "index_table_codes_on_store_id"
    t.index ["token"], name: "index_table_codes_on_token", unique: true
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

  create_table "user_passkeys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.datetime "last_used_at"
    t.string "nickname", null: false
    t.text "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["external_id"], name: "index_user_passkeys_on_external_id", unique: true
    t.index ["user_id"], name: "index_user_passkeys_on_user_id"
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
    t.string "invoice_registration_number"
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "locked_at"
    t.string "login_name", null: false
    t.jsonb "mfa_recovery_code_digests", default: [], null: false
    t.datetime "otp_enabled_at"
    t.bigint "otp_last_used_timestep"
    t.text "otp_secret_ciphertext"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.integer "tax_rounding_method", default: 0, null: false
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.integer "user_type"
    t.string "webauthn_id"
    t.integer "session_version", default: 0, null: false
    t.datetime "suspended_at"
    t.string "suspended_reason"
    t.bigint "owner_id"
    t.integer "role", default: 0, null: false
    t.integer "point_yen_per_point", default: 0, null: false
    t.string "receipt_footer"
    t.boolean "digital_receipt_enabled", default: true, null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["login_name"], name: "index_users_on_login_name", unique: true
    t.index ["owner_id"], name: "index_users_on_owner_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
    t.index ["webauthn_id"], name: "index_users_on_webauthn_id", unique: true
  end

  create_table "webhooks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "url", null: false
    t.text "secret_ciphertext", null: false
    t.string "events", default: [], null: false, array: true
    t.boolean "active", default: true, null: false
    t.integer "failure_count", default: 0, null: false
    t.datetime "last_delivered_at"
    t.string "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_webhooks_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_keys", "users", on_delete: :cascade
  add_foreign_key "attendances", "employees"
  add_foreign_key "attendances", "pos_tokens", on_delete: :nullify
  add_foreign_key "attendances", "stores"
  add_foreign_key "audit_logs", "users", on_delete: :cascade
  add_foreign_key "cash_logs", "employees"
  add_foreign_key "cash_logs", "pos_tokens"
  add_foreign_key "cash_logs", "register_sessions"
  add_foreign_key "cash_movements", "employees"
  add_foreign_key "cash_movements", "pos_tokens"
  add_foreign_key "cash_movements", "register_sessions"
  add_foreign_key "cash_movements", "stores"
  add_foreign_key "coupons", "users", on_delete: :cascade
  add_foreign_key "customer_displays", "pos_tokens", on_delete: :cascade
  add_foreign_key "customers", "users", on_delete: :cascade
  add_foreign_key "employee_permissions", "employees"
  add_foreign_key "employees", "users"
  add_foreign_key "hold_orders", "stores"
  add_foreign_key "journal_anchors", "pos_tokens", on_delete: :cascade
  add_foreign_key "journal_entries", "employees"
  add_foreign_key "journal_entries", "pos_tokens"
  add_foreign_key "journal_entries", "stores"
  add_foreign_key "journal_entries", "users"
  add_foreign_key "kitchen_orders", "stores", on_delete: :cascade
  add_foreign_key "operator_approvals", "employees"
  add_foreign_key "operator_approvals", "pos_tokens"
  add_foreign_key "option_groups", "users", on_delete: :cascade
  add_foreign_key "option_groups_products", "option_groups", on_delete: :cascade
  add_foreign_key "option_groups_products", "products", on_delete: :cascade
  add_foreign_key "option_items", "option_groups", on_delete: :cascade
  add_foreign_key "point_transactions", "customers"
  add_foreign_key "point_transactions", "refunds"
  add_foreign_key "point_transactions", "sales"
  add_foreign_key "pos_tokens", "provisionings"
  add_foreign_key "pos_tokens", "stores"
  add_foreign_key "prices", "products"
  add_foreign_key "prices", "stores"
  add_foreign_key "product_bundle_items", "product_bundles"
  add_foreign_key "product_bundle_items", "products"
  add_foreign_key "product_bundles", "users"
  add_foreign_key "product_categories", "users"
  add_foreign_key "product_imports", "users", on_delete: :cascade
  add_foreign_key "product_price_histories", "products", on_delete: :cascade
  add_foreign_key "product_price_histories", "stores", on_delete: :cascade
  add_foreign_key "products", "product_categories"
  add_foreign_key "products", "suppliers", on_delete: :nullify
  add_foreign_key "products", "users"
  add_foreign_key "products_promotions", "products", on_delete: :cascade
  add_foreign_key "products_promotions", "promotions", on_delete: :cascade
  add_foreign_key "promotions", "product_categories", on_delete: :cascade
  add_foreign_key "promotions", "users", on_delete: :cascade
  add_foreign_key "provisionings", "stores"
  add_foreign_key "provisionings", "users"
  add_foreign_key "purchase_order_items", "products"
  add_foreign_key "purchase_order_items", "purchase_orders", on_delete: :cascade
  add_foreign_key "purchase_orders", "stores"
  add_foreign_key "purchase_orders", "suppliers"
  add_foreign_key "purchase_orders", "users", on_delete: :cascade
  add_foreign_key "receivable_transactions", "customers"
  add_foreign_key "receivable_transactions", "refunds"
  add_foreign_key "receivable_transactions", "sales"
  add_foreign_key "refund_details", "products"
  add_foreign_key "refund_details", "refunds"
  add_foreign_key "refund_details", "saledetails"
  add_foreign_key "refund_payments", "refunds"
  add_foreign_key "refund_tax_breakdowns", "refunds"
  add_foreign_key "refunds", "employees"
  add_foreign_key "refunds", "pos_tokens"
  add_foreign_key "refunds", "register_sessions"
  add_foreign_key "refunds", "sales"
  add_foreign_key "refunds", "stores"
  add_foreign_key "refunds", "users"
  add_foreign_key "register_sessions", "employees", column: "closing_employee_id"
  add_foreign_key "register_sessions", "employees", column: "opening_employee_id"
  add_foreign_key "register_sessions", "pos_tokens"
  add_foreign_key "register_sessions", "stores"
  add_foreign_key "register_sessions", "users"
  add_foreign_key "reservations", "customers", on_delete: :nullify
  add_foreign_key "reservations", "stores", on_delete: :cascade
  add_foreign_key "sale_payments", "sales"
  add_foreign_key "sale_tax_breakdowns", "sales"
  add_foreign_key "saledetails", "products"
  add_foreign_key "saledetails", "sales"
  add_foreign_key "sales", "coupons"
  add_foreign_key "sales", "customers"
  add_foreign_key "sales", "employees"
  add_foreign_key "sales", "employees", column: "discount_approver_id"
  add_foreign_key "sales", "employees", column: "voided_by_employee_id"
  add_foreign_key "sales", "pos_tokens"
  add_foreign_key "sales", "register_sessions"
  add_foreign_key "sales", "stores"
  add_foreign_key "sales", "users"
  add_foreign_key "scheduled_product_changes", "products", on_delete: :cascade
  add_foreign_key "scheduled_product_changes", "stores", on_delete: :cascade
  add_foreign_key "scheduled_product_changes", "users", on_delete: :cascade
  add_foreign_key "stock_movements", "employees"
  add_foreign_key "stock_movements", "pos_tokens"
  add_foreign_key "stock_movements", "products"
  add_foreign_key "stock_movements", "sales"
  add_foreign_key "stock_movements", "store_stocks"
  add_foreign_key "stock_movements", "stores"
  add_foreign_key "stocktake_items", "employees"
  add_foreign_key "stocktake_items", "products"
  add_foreign_key "stocktake_items", "stocktakes", on_delete: :cascade
  add_foreign_key "stocktakes", "stores"
  add_foreign_key "stocktakes", "users", on_delete: :cascade
  add_foreign_key "store_stocks", "products"
  add_foreign_key "store_stocks", "stores"
  add_foreign_key "stores", "users"
  add_foreign_key "suppliers", "users", on_delete: :cascade
  add_foreign_key "table_codes", "stores", on_delete: :cascade
  add_foreign_key "table_orders", "stores"
  add_foreign_key "transfer_orders", "stores"
  add_foreign_key "user_passkeys", "users"
  add_foreign_key "users", "users", column: "owner_id"
  add_foreign_key "webhooks", "users", on_delete: :cascade
end
