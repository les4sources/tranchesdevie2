require 'rails_helper'

# Signalement d'un problème au retrait depuis « Mon compte » (#remboursement-partiel).
RSpec.describe 'Customers::OrderIssues', type: :request do
  let(:customer) { create(:customer, email: "cliente@example.com", email_opt_out: false) }
  let(:bake_day) { create(:bake_day, baked_on: Date.current) }
  let(:order) { create(:order, :ready, customer: customer, bake_day: bake_day, total_cents: 1_100) }
  let!(:item) { create(:order_item, order: order, qty: 2, unit_price_cents: 550) }

  # Les e-mails d'équipe partent en `deliver_later` : l'adaptateur de test est
  # ce qui permet de les observer sans les délivrer.
  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = original_adapter
  end

  def authenticate_customer
    allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
    allow(OtpService).to receive(:verify_code).and_return({ success: true })

    post '/connexion', params: { identifier: customer.phone_e164 }
    post '/connexion', params: { identifier: customer.phone_e164, otp_code: '123456' }
  end

  it 'exige une session client' do
    get customers_new_order_issue_path(order)
    expect(response).to redirect_to(customer_login_path)
  end

  context 'connecté' do
    before { authenticate_customer }

    it 'affiche le formulaire avec les articles de la commande' do
      get customers_new_order_issue_path(order)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(name="reported_items[#{item.id}]"))
    end

    it 'enregistre le signalement, ses lignes, et prévient l\'équipe' do
      expect {
        post customers_order_issues_path(order), params: {
          order_issue: { description: "Il manquait un pain." },
          reported_items: { item.id.to_s => "1" }
        }
      }.to change(OrderIssue, :count).by(1)
        .and have_enqueued_mail(OrderIssueMailer, :reported)

      issue = OrderIssue.last
      expect(issue.order).to eq(order)
      expect(issue.order_issue_items.first.qty).to eq(1)
      expect(response).to redirect_to(customers_account_path)
    end

    it 'refuse un signalement vide' do
      expect {
        post customers_order_issues_path(order), params: { order_issue: { description: "  " } }
      }.not_to change(OrderIssue, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'borne la quantité signalée à la quantité commandée' do
      post customers_order_issues_path(order), params: {
        order_issue: { description: "Deux pains manquants au moins." },
        reported_items: { item.id.to_s => "9" }
      }

      expect(OrderIssue.last.order_issue_items.first.qty).to eq(2)
    end

    it 'refuse une commande trop ancienne' do
      old_bake_day = create(:bake_day, baked_on: 2.months.ago.to_date)
      old_order = create(:order, :picked_up, customer: customer, bake_day: old_bake_day, total_cents: 1_100)

      get customers_new_order_issue_path(old_order)

      expect(response).to redirect_to(customers_account_path)
    end

    it "refuse la commande d'un autre client" do
      other = create(:order, :ready, bake_day: bake_day, total_cents: 1_100)

      get customers_new_order_issue_path(other)

      expect(response).to redirect_to(customers_account_path)
    end

    it 'propose le lien depuis Mon compte' do
      get customers_account_path

      expect(response.body).to include(customers_new_order_issue_path(order))
    end
  end
end
