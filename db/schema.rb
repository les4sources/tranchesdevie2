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

ActiveRecord::Schema[8.0].define(version: 2026_02_03_062411) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", precision: nil, null: false
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
    t.datetime "created_at", precision: nil, null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_pages", force: :cascade do |t|
    t.string "slug", null: false
    t.string "title", null: false
    t.text "body"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["slug"], name: "index_admin_pages_on_slug", unique: true
  end

  create_table "bake_days", force: :cascade do |t|
    t.date "baked_on", null: false
    t.timestamptz "cut_off_at", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "internal_note"
    t.index ["baked_on"], name: "index_bake_days_on_baked_on", unique: true
  end

  create_table "customers", force: :cascade do |t|
    t.string "phone_e164"
    t.string "first_name", null: false
    t.string "last_name"
    t.string "email"
    t.boolean "sms_opt_out", default: false, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "group_id"
    t.index ["group_id"], name: "index_customers_on_group_id"
    t.index ["phone_e164"], name: "index_customers_on_phone_e164", unique: true, where: "(phone_e164 IS NOT NULL)"
  end

  create_table "groups", force: :cascade do |t|
    t.string "name", null: false
    t.integer "discount_percent", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "ingredients", force: :cascade do |t|
    t.string "name", null: false
    t.integer "unit_type", default: 0, null: false
    t.integer "position", default: 0
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_ingredients_on_deleted_at"
    t.index ["name"], name: "index_ingredients_on_name", unique: true, where: "(deleted_at IS NULL)"
  end

  create_table "order_items", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "product_variant_id", null: false
    t.integer "qty", null: false
    t.integer "unit_price_cents", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
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
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "requires_invoice", default: false, null: false
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
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["order_id"], name: "index_payments_on_order_id", unique: true
    t.index ["status"], name: "index_payments_on_status"
    t.index ["stripe_payment_intent_id"], name: "index_payments_on_stripe_payment_intent_id", unique: true
  end

  create_table "phone_verifications", force: :cascade do |t|
    t.string "phone_e164", null: false
    t.string "code", limit: 6, null: false
    t.datetime "expires_at", precision: nil, null: false
    t.integer "attempts_count", default: 0, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["code"], name: "index_phone_verifications_on_code"
    t.index ["phone_e164"], name: "index_phone_verifications_on_phone_e164"
  end

  create_table "product_availabilities", force: :cascade do |t|
    t.bigint "product_variant_id", null: false
    t.date "start_on", null: false
    t.date "end_on"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["product_variant_id"], name: "index_product_availabilities_on_product_variant_id"
    t.index ["start_on", "end_on"], name: "index_product_availabilities_on_start_on_and_end_on"
  end

  create_table "product_images", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "product_variant_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "position"
    t.index ["product_id"], name: "index_product_images_on_product_id"
    t.index ["product_variant_id", "position"], name: "index_product_images_on_variant_and_position"
    t.index ["product_variant_id"], name: "index_product_images_on_product_variant_id"
  end

  create_table "product_variants", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.string "name", null: false
    t.integer "price_cents", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "flour_quantity"
    t.string "channel", default: "store", null: false
    t.index ["product_id"], name: "index_product_variants_on_product_id"
  end

  create_table "products", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.integer "category", default: 0, null: false
    t.integer "position", default: 0
    t.boolean "active", default: true, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "flour_quantity"
    t.string "short_name"
    t.string "flour"
    t.string "channel", default: "store", null: false
    t.datetime "deleted_at"
    t.index ["category", "position", "name"], name: "index_products_on_category_and_position_and_name"
    t.index ["category"], name: "index_products_on_category"
    t.index ["deleted_at"], name: "index_products_on_deleted_at"
  end

  create_table "sms_messages", force: :cascade do |t|
    t.integer "direction", default: 0, null: false
    t.string "to_e164", null: false
    t.string "from_e164", null: false
    t.date "baked_on"
    t.text "body", null: false
    t.integer "kind", default: 0, null: false
    t.string "external_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "customer_id"
    t.datetime "sent_at", precision: nil
    t.index ["customer_id"], name: "index_sms_messages_on_customer_id"
    t.index ["direction"], name: "index_sms_messages_on_direction"
    t.index ["external_id"], name: "index_sms_messages_on_external_id"
    t.index ["kind"], name: "index_sms_messages_on_kind"
    t.index ["to_e164"], name: "index_sms_messages_on_to_e164"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", precision: nil, null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", precision: nil, null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", precision: nil, null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at", precision: nil
    t.datetime "finished_at", precision: nil
    t.string "concurrency_key"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", precision: nil, null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", precision: nil, null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", precision: nil, null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", precision: nil, null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", precision: nil, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "stripe_events", force: :cascade do |t|
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.datetime "processed_at", precision: nil
    t.jsonb "payload"
    t.bigint "tenant_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["event_id"], name: "index_stripe_events_on_event_id", unique: true
    t.index ["event_type"], name: "index_stripe_events_on_event_type"
    t.index ["tenant_id"], name: "index_stripe_events_on_tenant_id"
  end

  create_table "variant_group_restrictions", force: :cascade do |t|
    t.bigint "product_variant_id", null: false
    t.bigint "group_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["group_id"], name: "index_variant_group_restrictions_on_group_id"
    t.index ["product_variant_id", "group_id"], name: "idx_variant_group_restrictions_unique", unique: true
    t.index ["product_variant_id"], name: "index_variant_group_restrictions_on_product_variant_id"
  end

  create_table "variant_ingredients", force: :cascade do |t|
    t.bigint "product_variant_id", null: false
    t.bigint "ingredient_id", null: false
    t.decimal "quantity", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ingredient_id"], name: "index_variant_ingredients_on_ingredient_id"
    t.index ["product_variant_id", "ingredient_id"], name: "index_variant_ingredients_on_variant_and_ingredient", unique: true
    t.index ["product_variant_id"], name: "index_variant_ingredients_on_product_variant_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id", name: "active_storage_attachments_blob_id_fkey"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id", name: "active_storage_variant_records_blob_id_fkey"
  add_foreign_key "customers", "groups", name: "customers_group_id_fkey"
  add_foreign_key "order_items", "orders", name: "order_items_order_id_fkey"
  add_foreign_key "order_items", "product_variants", name: "order_items_product_variant_id_fkey"
  add_foreign_key "orders", "bake_days", name: "orders_bake_day_id_fkey"
  add_foreign_key "orders", "customers", name: "orders_customer_id_fkey"
  add_foreign_key "payments", "orders", name: "payments_order_id_fkey"
  add_foreign_key "product_availabilities", "product_variants", name: "product_availabilities_product_variant_id_fkey"
  add_foreign_key "product_images", "product_variants", name: "product_images_product_variant_id_fkey"
  add_foreign_key "product_images", "products", name: "product_images_product_id_fkey"
  add_foreign_key "product_variants", "products", name: "product_variants_product_id_fkey"
  add_foreign_key "sms_messages", "customers", name: "sms_messages_customer_id_fkey"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", name: "solid_queue_blocked_executions_job_id_fkey", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", name: "solid_queue_claimed_executions_job_id_fkey", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", name: "solid_queue_failed_executions_job_id_fkey", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", name: "solid_queue_ready_executions_job_id_fkey", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", name: "solid_queue_recurring_executions_job_id_fkey", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", name: "solid_queue_scheduled_executions_job_id_fkey", on_delete: :cascade
  add_foreign_key "variant_group_restrictions", "groups"
  add_foreign_key "variant_group_restrictions", "product_variants"
  add_foreign_key "variant_ingredients", "ingredients"
  add_foreign_key "variant_ingredients", "product_variants"
end
