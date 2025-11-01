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

ActiveRecord::Schema[8.0].define(version: 2025_11_01_220611) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "admin_pages", force: :cascade do |t|
    t.string "slug", null: false
    t.string "title", null: false
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_admin_pages_on_slug", unique: true
  end

  create_table "bake_days", force: :cascade do |t|
    t.date "baked_on", null: false
    t.timestamptz "cut_off_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["baked_on"], name: "index_bake_days_on_baked_on", unique: true
  end

  create_table "customers", force: :cascade do |t|
    t.string "phone_e164", null: false
    t.string "first_name", null: false
    t.string "last_name"
    t.string "email"
    t.boolean "sms_opt_out", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["phone_e164"], name: "index_customers_on_phone_e164", unique: true
  end

  create_table "order_items", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "product_variant_id", null: false
    t.integer "qty", null: false
    t.integer "unit_price_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_variant_id"], name: "index_order_items_on_product_variant_id"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.bigint "bake_day_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "total_cents", null: false
    t.string "public_token", limit: 24, null: false
    t.string "order_number", null: false
    t.string "payment_intent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bake_day_id"], name: "index_orders_on_bake_day_id"
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["order_number"], name: "index_orders_on_order_number"
    t.index ["payment_intent_id"], name: "index_orders_on_payment_intent_id", unique: true, where: "(payment_intent_id IS NOT NULL)"
    t.index ["public_token"], name: "index_orders_on_public_token", unique: true
    t.index ["status"], name: "index_orders_on_status"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "stripe_payment_intent_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_payments_on_order_id", unique: true
    t.index ["status"], name: "index_payments_on_status"
    t.index ["stripe_payment_intent_id"], name: "index_payments_on_stripe_payment_intent_id", unique: true
  end

  create_table "phone_verifications", force: :cascade do |t|
    t.string "phone_e164", null: false
    t.string "code", limit: 6, null: false
    t.datetime "expires_at", null: false
    t.integer "attempts_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_phone_verifications_on_code"
    t.index ["phone_e164"], name: "index_phone_verifications_on_phone_e164"
  end

  create_table "product_availabilities", force: :cascade do |t|
    t.bigint "product_variant_id", null: false
    t.date "start_on", null: false
    t.date "end_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_variant_id"], name: "index_product_availabilities_on_product_variant_id"
    t.index ["start_on", "end_on"], name: "index_product_availabilities_on_start_on_and_end_on"
  end

  create_table "product_variants", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.string "name", null: false
    t.integer "price_cents", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_product_variants_on_product_id"
  end

  create_table "products", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.integer "category", default: 0, null: false
    t.integer "position", default: 0
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category", "position", "name"], name: "index_products_on_category_and_position_and_name"
    t.index ["category"], name: "index_products_on_category"
  end

  create_table "sms_messages", force: :cascade do |t|
    t.integer "direction", default: 0, null: false
    t.string "to_e164", null: false
    t.string "from_e164", null: false
    t.date "baked_on"
    t.text "body", null: false
    t.integer "kind", default: 0, null: false
    t.string "external_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["direction"], name: "index_sms_messages_on_direction"
    t.index ["external_id"], name: "index_sms_messages_on_external_id"
    t.index ["kind"], name: "index_sms_messages_on_kind"
    t.index ["to_e164"], name: "index_sms_messages_on_to_e164"
  end

  create_table "stripe_events", force: :cascade do |t|
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.datetime "processed_at", precision: nil
    t.jsonb "payload"
    t.bigint "tenant_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_stripe_events_on_event_id", unique: true
    t.index ["event_type"], name: "index_stripe_events_on_event_type"
    t.index ["tenant_id"], name: "index_stripe_events_on_tenant_id"
  end

  create_table "tenants", force: :cascade do |t|
    t.string "subdomain", null: false
    t.string "custom_domain"
    t.string "name", null: false
    t.text "pickup_address"
    t.string "timezone", default: "Europe/Brussels"
    t.string "logo_url"
    t.string "primary_color", limit: 7
    t.string "telerivet_project_id"
    t.string "telerivet_phone_id"
    t.string "telerivet_api_key"
    t.string "stripe_account_id"
    t.jsonb "production_defaults"
    t.string "status", default: "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["custom_domain"], name: "index_tenants_on_custom_domain", unique: true
    t.index ["subdomain"], name: "index_tenants_on_subdomain", unique: true
  end

  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "product_variants"
  add_foreign_key "orders", "bake_days"
  add_foreign_key "orders", "customers"
  add_foreign_key "payments", "orders"
  add_foreign_key "product_availabilities", "product_variants"
  add_foreign_key "product_variants", "products"
  add_foreign_key "stripe_events", "tenants"
end
