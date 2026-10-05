require "rails_helper"
require "pdf/reader"

RSpec.describe "Admin::DeliveryNotes", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  let(:order) do
    create(:order, total_cents: 1100).tap do |o|
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
end
