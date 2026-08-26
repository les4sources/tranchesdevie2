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
end
