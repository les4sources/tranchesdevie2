require 'rails_helper'

# Paiement différé d'une réservation de Pizza party validée (#pizza-parties).
#
# Le cœur du lot : la page vit hors session, le nombre de participants se
# confirme ICI, et le montant du PaymentIntent doit suivre la commande — sans
# quoi un client qui revient sur ses pas paierait le chiffre de sa première visite.
RSpec.describe "Paiement d'une réservation de Pizza party", type: :request do
  let!(:party_product) { create(:product, :pizza_party) }
  let!(:party_variant) { create(:product_variant, product: party_product, price_cents: 1200) }
  let!(:forfait_product) { create(:product, :pizza_party_forfait) }
  let!(:forfait_variant) { create(:product_variant, product: forfait_product, price_cents: 4000, channel: "admin") }

  # Toute commande a un lieu de retrait ; une party retombe sur le lieu par
  # défaut (Les 4 Sources), cf. Order#assign_default_pickup_location.
  let!(:default_pickup) { create(:pickup_location, name: "Les 4 Sources", default: true) }
  # Identifiants explicites : la base de test est partagée entre agents et les
  # séquences de factory finissent par entrer en collision.
  let(:customer) { create(:customer, phone_e164: "+32470400400", email: "paiement@example.com") }
  let(:party_request) { create(:party_request, customer: customer) }

  # Une réservation validée : la demande est passée par le service de décision,
  # donc l'Order existe en awaiting_payment avec ses lignes figées.
  let(:order) do
    PartyRequestService.new(
      customer: customer,
      date: party_request.held_on,
      slot: "soir",
      customer_note: "Anniversaire."
    ).call.then { |request| PartyDecisionService.new(request, decided_by: "Romane").accept }
  end

  def stripe_intent(id: "pi_test_123", status: "requires_payment_method", amount: 0)
    double(id: id, status: status, amount: amount, client_secret: "#{id}_secret")
  end

  describe "GET /reservations/:token/paiement" do
    it "affiche la page de règlement pour une réservation validée" do
      get party_payment_path(token: order.public_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Combien serez-vous")
    end

    it "renvoie vers la page de confirmation si la commande n'est plus à régler" do
      order.update!(status: :paid)

      get party_payment_path(token: order.public_token)
      expect(response).to redirect_to(party_payment_success_path(token: order.public_token))
    end

    it "ne demande aucune session : un visiteur non connecté y accède" do
      get party_payment_path(token: order.public_token)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST confirmation du nombre + PaymentIntent" do
    before do
      allow(Stripe::PaymentIntent).to receive(:create).and_return(stripe_intent)
    end

    it "recalcule le total sur le nombre confirmé, aux prix figés" do
      post party_payment_intent_path(token: order.public_token), params: { persons: 12 }

      expect(response).to have_http_status(:ok)
      # 12 pâtons à 12,00 € + forfait 40,00 €
      expect(order.reload.total_cents).to eq(12 * 1200 + 4000)
      expect(JSON.parse(response.body)["total_cents"]).to eq(12 * 1200 + 4000)
    end

    it "ignore un changement de tarif survenu après la demande" do
      # La demande (et son gel de prix) doit exister AVANT le changement de tarif :
      # `order` est paresseux, le référencer ici fixe l'ordre des faits.
      order
      party_variant.update!(price_cents: 2500)

      post party_payment_intent_path(token: order.public_token), params: { persons: 10 }

      expect(order.reload.total_cents).to eq(10 * 1200 + 4000)
    end

    it "met la ligne de commande au nombre confirmé (pâtons à préparer)" do
      post party_payment_intent_path(token: order.public_token), params: { persons: 20 }

      expect(order.reload.party_paton_count).to eq(20)
    end

    it "refuse un nombre inférieur à 1 et ne débite rien" do
      post party_payment_intent_path(token: order.public_token), params: { persons: 0 }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Stripe::PaymentIntent).not_to have_received(:create)
    end

    it "crée le PaymentIntent depuis la commande, sans panier ni session" do
      post party_payment_intent_path(token: order.public_token), params: { persons: 9 }

      expect(Stripe::PaymentIntent).to have_received(:create).with(
        hash_including(amount: 9 * 1200 + 4000, currency: "eur")
      )
      expect(JSON.parse(response.body)["client_secret"]).to eq("pi_test_123_secret")
    end
  end

  describe "contrôle de capacité à la confirmation" do
    let(:flour) { create(:flour, kneader_limit_grams: 5_000) }

    before do
      create(:product_flour, product: party_product, flour: flour, percentage: 100)
      party_variant.update!(flour_quantity: 250)
      allow(Stripe::PaymentIntent).to receive(:create).and_return(stripe_intent)
    end

    it "refuse une hausse qui ferait sauter le pétrin, sans rien débiter" do
      create(:bake_day, baked_on: order.party_event.held_on)

      # 25 pâtons × 250 g = 6 250 g, au-delà des 5 kg du pétrin.
      post party_payment_intent_path(token: order.public_token), params: { persons: 25 }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/Pétrin/)
      expect(Stripe::PaymentIntent).not_to have_received(:create)
      expect(order.reload.party_paton_count).to eq(1)
    end

    it "laisse passer une hausse que la fournée supporte" do
      create(:bake_day, baked_on: order.party_event.held_on)

      post party_payment_intent_path(token: order.public_token), params: { persons: 12 }

      expect(response).to have_http_status(:ok)
      expect(order.reload.party_paton_count).to eq(12)
    end

    it "ne bloque pas le paiement quand la fournée du jour n'existe pas encore" do
      expect(BakeDay.find_by(baked_on: order.party_event.held_on)).to be_nil

      post party_payment_intent_path(token: order.public_token), params: { persons: 40 }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "réutilisation du PaymentIntent" do
    it "réutilise le PI vivant et met son montant à jour au lieu d'en créer un second" do
      order.update!(payment_intent_id: "pi_live")
      allow(Stripe::PaymentIntent).to receive(:retrieve).with("pi_live")
        .and_return(stripe_intent(id: "pi_live", amount: 13_600))
      allow(Stripe::PaymentIntent).to receive(:update).and_return(true)
      allow(Stripe::PaymentIntent).to receive(:create)

      post party_payment_intent_path(token: order.public_token), params: { persons: 20 }

      expect(Stripe::PaymentIntent).to have_received(:update).with("pi_live", amount: 20 * 1200 + 4000)
      expect(Stripe::PaymentIntent).not_to have_received(:create)
    end

    it "crée un nouveau PI quand l'ancien est annulé" do
      order.update!(payment_intent_id: "pi_dead")
      allow(Stripe::PaymentIntent).to receive(:retrieve).with("pi_dead")
        .and_return(stripe_intent(id: "pi_dead", status: "canceled"))
      allow(Stripe::PaymentIntent).to receive(:create).and_return(stripe_intent(id: "pi_new"))

      post party_payment_intent_path(token: order.public_token), params: { persons: 8 }

      expect(Stripe::PaymentIntent).to have_received(:create)
      expect(order.reload.payment_intent_id).to eq("pi_new")
    end
  end

  describe "GET /reservations/:token/merci" do
    it "encaisse via OrderPaymentFinalizer quand le PaymentIntent a abouti" do
      order.update!(payment_intent_id: "pi_ok")
      allow(Stripe::PaymentIntent).to receive(:retrieve).with("pi_ok")
        .and_return(stripe_intent(id: "pi_ok", status: "succeeded"))

      get party_payment_success_path(token: order.public_token), params: { payment_intent: "pi_ok" }

      expect(order.reload).to be_paid
      expect(response.body).to include("confirmée")
    end

    it "signale un écart entre le montant encaissé et la commande, sans bloquer" do
      order.update!(payment_intent_id: "pi_ecart")
      allow(Stripe::PaymentIntent).to receive(:retrieve).with("pi_ecart")
        .and_return(stripe_intent(id: "pi_ecart", status: "succeeded", amount: 999))
      allow(Rails.logger).to receive(:error)

      get party_payment_success_path(token: order.public_token), params: { payment_intent: "pi_ecart" }

      expect(Rails.logger).to have_received(:error).with(/montant encaissé 999/)
      expect(order.reload).to be_paid
    end

    it "n'encaisse pas un paiement encore en cours" do
      order.update!(payment_intent_id: "pi_processing")
      allow(Stripe::PaymentIntent).to receive(:retrieve).with("pi_processing")
        .and_return(stripe_intent(id: "pi_processing", status: "processing"))

      get party_payment_success_path(token: order.public_token), params: { payment_intent: "pi_processing" }

      expect(order.reload).to be_awaiting_payment
      expect(response.body).to include("en cours de traitement")
    end
  end

  describe "anti-régressions" do
    it "aucun chemin portefeuille n'est exposé sur ce parcours" do
      get party_payment_path(token: order.public_token)

      # Le lien « Mon portefeuille » du pied de page global ne compte pas : ce
      # qu'on interdit, c'est un MOYEN DE PAIEMENT portefeuille sur cette page.
      expect(response.body).not_to include("wallet-order-section")
      expect(response.body).not_to include('value="wallet"')
      expect(response.body).not_to match(/payer avec (mon|le) portefeuille/i)
    end

    it "la commande naît hors du chiffre d'affaires et hors production" do
      expect(Order.completed).not_to include(order)
      expect(Order::COMPLETED_STATUSES).not_to include("awaiting_payment")
    end
  end
end
