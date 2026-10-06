require "rails_helper"
require "pdf/reader"

RSpec.describe "Admin::DeliveryNotes", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  let(:delivered) { create(:customer, billable: true, delivered_by_bakery: true) }
  let(:order) do
    create(:order, customer: delivered, total_cents: 1100).tap do |o|
      create(:order_item, order: o, qty: 2, unit_price_cents: 550)
    end
  end

  it "exige une authentification admin" do
    get admin_order_delivery_note_path(order_id: order.id)
    expect(response).to redirect_to(admin_login_path)
  end

  it "renvoie le bon de livraison en PDF" do
    post admin_login_path, params: { password: "test-admin-pw" }
    get admin_order_delivery_note_path(order_id: order.id)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(response.headers["Content-Disposition"]).to include("attachment").and include("bon-de-livraison-BL-")
    text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
    expect(text).to include("BON DE LIVRAISON")
  end

  it "refuse le bon d'un client facturable que la boulangerie ne livre pas" do
    collected = create(:order, total_cents: 550, customer: create(:customer, billable: true)).tap do |o|
      create(:order_item, order: o, qty: 1, unit_price_cents: 550)
    end
    post admin_login_path, params: { password: "test-admin-pw" }
    get admin_order_delivery_note_path(order_id: collected.id)

    expect(response).to redirect_to(admin_billing_path)
    expect(flash[:alert]).to include("pas livré par la boulangerie")
  end

  describe "bons de livraison d'une journée de cuisson" do
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let!(:order_a) do
      create(:order, bake_day: bake_day, status: :paid, total_cents: 550,
        customer: create(:customer, billable: true, delivered_by_bakery: true, first_name: "Alice", last_name: "Martin")).tap do |o|
        create(:order_item, order: o, qty: 1, unit_price_cents: 550)
      end
    end
    let!(:order_b) do
      create(:order, bake_day: bake_day, status: :ready, total_cents: 1100,
        customer: create(:customer, billable: true, delivered_by_bakery: true, first_name: "Bruno", last_name: "Lambert")).tap do |o|
        create(:order_item, order: o, qty: 2, unit_price_cents: 550)
      end
    end
    let!(:cancelled) do
      create(:order, bake_day: bake_day, status: :cancelled, total_cents: 550,
        customer: create(:customer, billable: true, delivered_by_bakery: true, first_name: "Chloé", last_name: "Annulée")).tap do |o|
        create(:order_item, order: o, qty: 1, unit_price_cents: 550)
      end
    end

    let!(:individual) do
      create(:order, bake_day: bake_day, status: :paid, total_cents: 550,
        customer: create(:customer, billable: false, first_name: "Denis", last_name: "Particulier")).tap do |o|
        create(:order_item, order: o, qty: 1, unit_price_cents: 550)
      end
    end

    let!(:not_delivered) do
      create(:order, bake_day: bake_day, status: :paid, total_cents: 550,
        customer: create(:customer, billable: true, delivered_by_bakery: false, first_name: "Emma", last_name: "Enlèvement")).tap do |o|
        create(:order_item, order: o, qty: 1, unit_price_cents: 550)
      end
    end

    before { post admin_login_path, params: { password: "test-admin-pw" } }

    it "regroupe un bon par commande de client livré par la boulangerie dans un seul PDF" do
      get delivery_notes_admin_bake_day_path(bake_day)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("bons-de-livraison-2026-05-12.pdf")

      pages = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text)
      expect(pages.size).to eq(2)
      expect(pages[0]).to include("Alice Martin", order_a.order_number)
      expect(pages[1]).to include("Bruno Lambert", order_b.order_number)
      expect(pages.join).not_to include("Chloé")
      expect(pages.join).not_to include("Particulier")
      expect(pages.join).not_to include("Enlèvement")
    end

    it "redirige avec une alerte quand la journée n'a aucune commande de client livré" do
      empty = create(:bake_day, baked_on: Date.new(2026, 5, 15))
      get delivery_notes_admin_bake_day_path(empty)

      expect(response).to redirect_to(admin_bake_day_path(empty))
      expect(flash[:alert]).to include("Aucune commande")
    end

    it "est proposé sur la page de la journée" do
      get admin_bake_day_path(bake_day)
      expect(response.body).to include(delivery_notes_admin_bake_day_path(bake_day))
    end
  end
end
