require 'rails_helper'

# Le commentaire du client (#169) doit être lisible par l'équipe dans l'admin.
RSpec.describe 'Admin — commentaire de la Pizza party privée', type: :request do
  around do |ex|
    original = ENV['ADMIN_PASSWORD']
    ENV['ADMIN_PASSWORD'] = 'test-admin-pw'
    ex.run
    ENV['ADMIN_PASSWORD'] = original
  end

  before { post admin_login_path, params: { password: 'test-admin-pw' } }

  let!(:default_pickup) { create(:pickup_location, :default) }
  let(:customer) { create(:customer, first_name: 'Léa') }
  let(:party_product) { create(:product, :pizza_party) }
  let(:party_variant) { create(:product_variant, product: party_product, name: 'une boule', price_cents: 500) }
  let(:note) { "On arrive vers 18h30 pour l'anniversaire de Jules, 3 enfants dont un sans gluten." }

  def party_order(customer_note:, held_on: Date.current + 8)
    PartyOrderCreationService.new(
      customer: customer,
      party_event: create(:party_event, :private_party, held_on: held_on),
      cart_items: [ { 'product_variant_id' => party_variant.id.to_s, 'qty' => '4' } ],
      customer_note: customer_note
    ).call
  end

  describe 'GET /admin/orders/:id' do
    it 'affiche le mot du client dans un bloc identifié' do
      order = party_order(customer_note: note)

      get admin_order_path(order)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Mot du client')
      expect(response.body).to include(CGI.escapeHTML(note))
    end

    it "s'affiche sans erreur pour une commande party ancienne, sans commentaire" do
      order = party_order(customer_note: nil)

      get admin_order_path(order)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Mot du client')
    end

    it "n'affiche pas de bloc commentaire sur une commande de pain" do
      bread_order = create(:order, customer: customer, bake_day: create(:bake_day, :can_order))

      get admin_order_path(bread_order)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Mot du client')
    end
  end

  describe 'GET /admin/parties' do
    it 'affiche le commentaire dans la ligne de la réservation privée' do
      party_order(customer_note: note)

      get admin_party_events_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Mot du client')
      expect(response.body).to include(CGI.escapeHTML(note.truncate(80)))
    end

    it "tronque un commentaire long tout en gardant le texte complet accessible" do
      long_note = "Bonjour, #{'nous sommes un groupe très bavard. ' * 20}"[0, 500]
      party_order(customer_note: long_note)

      get admin_party_events_path

      expect(response).to have_http_status(:ok)
      # Tronqué dans la cellule (truncate pose un « … » final)…
      expect(response.body).to include(CGI.escapeHTML(long_note.truncate(80)))
      expect(long_note.truncate(80)).to end_with("...")
      # …mais lisible en entier au survol.
      expect(response.body).to include("title=\"#{CGI.escapeHTML(long_note)}\"")
    end

    it "supporte une réservation privée sans commentaire" do
      party_order(customer_note: nil)

      get admin_party_events_path

      expect(response).to have_http_status(:ok)
    end
  end
end
