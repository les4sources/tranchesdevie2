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

ActiveRecord::Schema[8.0].define(version: 2025_10_23_002614) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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

  add_foreign_key "stripe_events", "tenants"
end
