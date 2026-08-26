require "rails_helper"

# Garde-fou N+1 sur la fiche d'une party publique (#173) : le contrôleur
# précharge client, lignes et variantes. Sans ce préchargement, chaque
# inscription coûterait plusieurs requêtes de plus.
RSpec.describe "Admin — requêtes de la fiche d'une party publique", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  def count_queries
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].to_s =~ /SCHEMA|TRANSACTION/ }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  it "ne fait pas croître le nombre de requêtes avec le nombre d'inscriptions" do
    create(:pickup_location, :default)
    product = create(:product, :pizza_party_public)
    adulte = create(:product_variant, product: product, name: "adulte", price_cents: 1_000)
    enfant = create(:product_variant, product: product, name: "enfant", price_cents: 600)
    event = create(:party_event, :public_party, title: "Grande party", capacity: 200)

    seq = 0
    register = lambda do |n|
      n.times do
        seq += 1
        cust = create(:customer, first_name: "C#{seq}", email: "c#{seq}@example.com")
        PartyOrderCreationService.new(
          customer: cust, party_event: event,
          cart_items: [
            { "product_variant_id" => adulte.id.to_s, "qty" => "2" },
            { "product_variant_id" => enfant.id.to_s, "qty" => "1" }
          ]
        ).call.update!(status: :paid)
      end
    end

    post admin_login_path, params: { password: "test-admin-pw" }

    register.call(3)
    with_three = count_queries { get admin_party_event_path(event) }

    register.call(12)
    with_fifteen = count_queries { get admin_party_event_path(event) }

    expect(response).to have_http_status(:ok)
    expect(with_fifteen - with_three).to be <= 2,
      "5× plus d'inscriptions ne doit pas coûter plus de requêtes " \
      "(#{with_three} → #{with_fifteen})"
  end
end
