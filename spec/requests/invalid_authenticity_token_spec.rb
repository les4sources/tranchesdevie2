require 'rails_helper'

# Jeton CSRF refusé (page ouverte longtemps, page restaurée du cache, cookies
# bloqués) : au lieu de la page anglaise « 422 Unprocessable Content », le
# client revient sur sa page avec une consigne claire, et Sentry est prévenu.
RSpec.describe 'Jeton CSRF invalide', type: :request do
  let!(:public_product) { create(:product, :pizza_party_public, channel: 'store') }
  let!(:adult_variant) { create(:product_variant, product: public_product, name: 'adulte', channel: 'store') }
  let!(:event) do
    create(:party_event, :public_party, held_on: Date.current + 14, capacity: 40,
                                        registration_closes_at: 10.days.from_now)
  end
  let(:params) { { product_variant_id: adult_variant.id, public_party_event_id: event.id, qty: 1, authenticity_token: 'périmé' } }

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  it 'renvoie sur la page d’origine avec un message, sans rien ajouter au panier' do
    post cart_add_path, params: params, headers: { 'HTTP_REFERER' => "http://www.example.com#{camembert_parties_path}" }

    expect(response).to redirect_to(camembert_parties_path)
    expect(flash[:alert]).to include("plus à jour")
    expect(session[:cart].to_a).to be_empty
  end

  it 'retombe sur l’accueil sans referer' do
    post cart_add_path, params: params

    expect(response).to redirect_to(root_path)
  end

  it 'répond en JSON lisible pour les ajouts en AJAX' do
    post cart_add_path, params: params, headers: { 'ACCEPT' => 'application/json' }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body['error']).to include('Recharge-la')
  end

  it 'laisse passer un jeton valide' do
    get camembert_parties_path
    token = response.body[/name="authenticity_token" value="([^"]+)"/, 1]

    post cart_add_path, params: params.merge(authenticity_token: token)

    expect(response).to redirect_to(camembert_parties_path)
    expect(session[:cart].sum { |i| i['qty'].to_i }).to eq(1)
  end
end
