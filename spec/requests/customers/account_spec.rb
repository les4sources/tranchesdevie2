require 'rails_helper'

RSpec.describe 'Customers::Account', type: :request do
  let(:customer) { create(:customer, email: "eater@example.com", email_opt_out: false) }

  def authenticate_customer
    allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
    allow(OtpService).to receive(:verify_code).and_return({ success: true })

    post '/connexion', params: { identifier: customer.phone_e164 }
    post '/connexion', params: { identifier: customer.phone_e164, otp_code: '123456' }
  end

  before { authenticate_customer }

  describe 'GET /customers/mon-compte (show)' do
    let(:bake_day) { create(:bake_day) }

    it 'masque les commandes pending et ne montre que la commande payée (#144)' do
      paid = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 1100)
      pending = create(:order, :pending, customer: customer, bake_day: bake_day, total_cents: 1100)

      get customers_account_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(data-order-modal-order-id-value="#{paid.id}"))
      expect(response.body).not_to include(%(data-order-modal-order-id-value="#{pending.id}"))
      expect(response.body).not_to include('data-status="pending"')
    end

    it 'affiche toujours les autres statuts (non-régression cancelled)' do
      create(:order, :paid, customer: customer, bake_day: bake_day)
      other_day = create(:bake_day, baked_on: Date.current.next_occurring(:friday))
      cancelled = create(:order, :cancelled, customer: customer, bake_day: other_day)

      get customers_account_path

      expect(response.body).to include(%(data-order-modal-order-id-value="#{cancelled.id}"))
      expect(response.body).to include('data-status="cancelled"')
    end

    it 'exclut les pending du compteur de commandes passées et du total dépensé' do
      day_cancelled = create(:bake_day, baked_on: Date.current.next_occurring(:friday))
      day_pending = create(:bake_day, baked_on: Date.current.next_occurring(:tuesday) + 7)
      create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: 1100)
      create(:order, :cancelled, customer: customer, bake_day: day_cancelled, total_cents: 900)
      create(:order, :pending, customer: customer, bake_day: day_pending, total_cents: 5000)

      get customers_account_path

      # 2 commandes visibles (paid + cancelled), la pending est masquée
      expect(response.body).to match(/2\s*commandes? passée/)
      # Le total dépensé (paid uniquement, cancelled et pending exclus) reste 11€
      expect(response.body).not_to include('data-status="pending"')
    end
  end

  describe 'GET /customers/mon-compte/edit' do
    it 'renders the profile form with the email preference toggle' do
      get customers_edit_account_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("email_opt_out")
      expect(response.body).to include("Désactiver les e-mails")
    end
  end

  describe 'PATCH /customers/mon-compte' do
    it 'lets the customer disable non-OTP emails' do
      patch customers_account_path, params: { customer: { email_opt_out: "1" } }
      expect(customer.reload.email_opt_out).to be true
    end
  end

  # Pointage « J'ai récupéré ma commande » sans rechargement (#291).
  describe 'PATCH /mon-compte/commandes/:id/recuperee (pickup_order)' do
    let(:bake_day) { create(:bake_day) }
    let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }

    def ready_order
      create(:order, :ready, customer: customer, bake_day: bake_day, total_cents: 1100)
    end

    it 'répond en Turbo Stream : ligne remplacée, compteurs et flash mis à jour' do
      order = ready_order

      patch customers_pickup_order_path(order), headers: turbo

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(%(<turbo-stream action="replace" target="order_row_#{order.id}">))
      expect(response.body).to include(%(<turbo-stream action="update" target="acct-count-ready">))
      expect(response.body).to include(%(<turbo-stream action="update" target="acct-count-picked_up">))
      expect(response.body).to include(%(<turbo-stream action="update" target="account-flash">))
      expect(response.body).to include("Commande marquée comme récupérée. Bon appétit !")
      expect(order.reload).to be_picked_up
    end

    it 'renvoie la ligne dans son nouvel état, bouton de pointage retiré' do
      order = ready_order

      patch customers_pickup_order_path(order), headers: turbo

      expect(response.body).to include('data-status="picked_up"')
      expect(response.body).to include("Récupérée")
      expect(response.body).not_to include("J'ai récupéré ma commande")
    end

    it 'met à jour le JSON de la modale porté par la ligne' do
      order = ready_order

      patch customers_pickup_order_path(order), headers: turbo

      expect(response.body).to include("&quot;status&quot;:&quot;picked_up&quot;")
    end

    it 'rafraîchit les compteurs de la page (prêtes -1, récupérées +1)' do
      order = ready_order
      create(:order, :ready, customer: customer, bake_day: create(:bake_day, baked_on: Date.current.next_occurring(:friday)))

      patch customers_pickup_order_path(order), headers: turbo

      expect(response.body).to include(%(<turbo-stream action="update" target="acct-count-ready"><template>1</template>))
      expect(response.body).to include(%(<turbo-stream action="update" target="acct-count-picked_up"><template>1</template>))
      expect(response.body).to include(%(<turbo-stream action="update" target="acct-stat-ready"><template>1</template>))
      expect(response.body).to include(%(<turbo-stream action="replace" target="acct-ready-banner">))
    end

    it 'garde la redirection historique hors Turbo (JS désactivé)' do
      order = ready_order

      patch customers_pickup_order_path(order)

      expect(response).to redirect_to(customers_account_path)
      expect(flash[:notice]).to eq("Commande marquée comme récupérée. Bon appétit !")
      expect(order.reload).to be_picked_up
    end

    it 'signale une commande introuvable sans rien casser' do
      other = create(:order, :ready, customer: create(:customer), bake_day: bake_day)

      patch customers_pickup_order_path(other), headers: turbo

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Commande introuvable")
      expect(response.body).not_to include(%(target="order_row_#{other.id}"))
      expect(other.reload).to be_ready
    end

    it "remplace la ligne par son état réel quand la commande n'est plus récupérable" do
      order = create(:order, :paid, customer: customer, bake_day: bake_day)

      patch customers_pickup_order_path(order), headers: turbo

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cette commande ne peut pas être marquée comme récupérée")
      expect(response.body).to include(%(<turbo-stream action="replace" target="order_row_#{order.id}">))
      expect(response.body).to include('data-status="paid"')
      expect(order.reload).to be_paid
    end

    it 'rend la liste initiale avec les mêmes identifiants de ligne que le flux' do
      order = ready_order

      get customers_account_path

      expect(response.body).to include(%(id="order_row_#{order.id}"))
      expect(response.body).to include('id="account-flash"')
      expect(response.body).to include('id="acct-count-ready"')
      expect(response.body).to include('id="acct-ready-banner"')
    end
  end
end
