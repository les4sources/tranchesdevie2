require 'rails_helper'

RSpec.describe SmsService do
  let(:customer) { create(:customer, sms_opt_out: false) }
  let(:bake_day) { create(:bake_day, :can_order) }
  let(:order) { create(:order, customer: customer, bake_day: bake_day, total_cents: 1500) }
  let(:wallet) { create(:wallet, customer: customer, balance_cents: 500) }

  let(:successful_response) do
    recipient = double(message_id: "msg_123", body: "rendered body")
    data = double(recipients: [ recipient ])
    double(data: data)
  end

  before do
    create(:sms_template, name: "confirmation", body: "Ta commande chez Tranches de Vie est confirmée. Merci !", variables: [])
    create(:sms_template, name: "ready_paid", body: "Bonjour, ta commande est prête !", variables: [])
    create(:sms_template, name: "ready_unpaid", body: "Bonjour, ta commande est prête (total {{0:amount}})", variables: [ { "id" => 0, "name" => "amount" } ])
    create(:sms_template, name: "refund", body: "Ta commande a été remboursée intégralement.", variables: [])
    create(:sms_template, name: "planned_confirmed", body: "Ta commande planifiée pour le {{0:bake_date}} a été validée ({{1:amount}} débité).", variables: [ { "id" => 0, "name" => "bake_date" }, { "id" => 1, "name" => "amount" } ])
    create(:sms_template, name: "planned_cancelled", body: "Ta commande planifiée pour le {{0:bake_date}} a été annulée car ton solde était insuffisant.", variables: [ { "id" => 0, "name" => "bake_date" } ])
    create(:sms_template, name: "low_balance", body: "Ton solde de portefeuille est bas ({{0:balance}}).", variables: [ { "id" => 0, "name" => "balance" } ])
    create(:sms_template, name: "insufficient_balance", body: "Il te manque {{0:amount_needed}} pour ta commande du {{1:bake_date}}.", variables: [ { "id" => 0, "name" => "amount_needed" }, { "id" => 1, "name" => "bake_date" } ])

    allow(SentDmClient).to receive(:send_message).and_return(successful_response)
  end

  describe '.send_confirmation' do
    it 'envoie le template confirmation' do
      expect(SentDmClient).to receive(:send_message).with(
        template_name: :confirmation,
        to: customer.phone_e164,
        parameters: {}
      ).and_return(successful_response)

      SmsService.send_confirmation(order)
    end

    it 'crée un SmsMessage' do
      expect { SmsService.send_confirmation(order) }.to change(SmsMessage, :count).by(1)
      expect(SmsMessage.last.kind).to eq("confirmation")
      expect(SmsMessage.last.external_id).to eq("msg_123")
    end

    it 'retourne false si SMS désactivés' do
      customer.update!(sms_opt_out: true)
      expect(SmsService.send_confirmation(order)).to be false
    end
  end

  describe '.send_ready' do
    context 'commande payée' do
      it 'envoie le template ready_paid sans paramètre' do
        allow(order).to receive(:unpaid_ready?).and_return(false)
        expect(SentDmClient).to receive(:send_message).with(
          template_name: :ready_paid,
          to: customer.phone_e164,
          parameters: {}
        ).and_return(successful_response)

        SmsService.send_ready(order)
      end
    end

    context 'commande non payée' do
      it 'envoie le template ready_unpaid avec le montant' do
        allow(order).to receive(:unpaid_ready?).and_return(true)
        allow(order).to receive(:total_euros).and_return(15)

        expect(SentDmClient).to receive(:send_message).with(
          template_name: :ready_unpaid,
          to: customer.phone_e164,
          parameters: hash_including(amount: a_string_matching(/15/))
        ).and_return(successful_response)

        SmsService.send_ready(order)
      end
    end
  end

  describe '.send_planned_order_confirmed' do
    it 'envoie le template avec montant et date' do
      expect(SentDmClient).to receive(:send_message).with(
        template_name: :planned_confirmed,
        to: customer.phone_e164,
        parameters: hash_including(:bake_date, :amount)
      ).and_return(successful_response)

      SmsService.send_planned_order_confirmed(order)
    end

    it 'crée un SmsMessage' do
      expect { SmsService.send_planned_order_confirmed(order) }.to change(SmsMessage, :count).by(1)
    end

    it 'retourne false si SMS désactivés' do
      customer.update!(sms_opt_out: true)
      expect(SmsService.send_planned_order_confirmed(order)).to be false
    end
  end

  describe '.send_planned_order_cancelled' do
    it 'envoie le template planned_cancelled' do
      expect(SentDmClient).to receive(:send_message).with(
        template_name: :planned_cancelled,
        to: customer.phone_e164,
        parameters: hash_including(:bake_date)
      ).and_return(successful_response)

      SmsService.send_planned_order_cancelled(order)
    end

    it 'crée un SmsMessage' do
      expect { SmsService.send_planned_order_cancelled(order) }.to change(SmsMessage, :count).by(1)
    end
  end

  describe '.send_insufficient_balance_warning' do
    before { wallet }

    it 'envoie le template avec le montant manquant et la date' do
      expect(SentDmClient).to receive(:send_message).with(
        template_name: :insufficient_balance,
        to: customer.phone_e164,
        parameters: hash_including(amount_needed: a_string_matching(/10/))
      ).and_return(successful_response)

      SmsService.send_insufficient_balance_warning(order)
    end

    it 'crée un SmsMessage' do
      expect { SmsService.send_insufficient_balance_warning(order) }.to change(SmsMessage, :count).by(1)
    end
  end

  describe '.send_low_balance_alert' do
    before { wallet }

    it 'envoie le template low_balance avec le solde' do
      expect(SentDmClient).to receive(:send_message).with(
        template_name: :low_balance,
        to: customer.phone_e164,
        parameters: hash_including(balance: a_string_matching(/5/))
      ).and_return(successful_response)

      SmsService.send_low_balance_alert(customer)
    end

    it 'retourne false si pas de portefeuille' do
      customer_without_wallet = create(:customer, sms_opt_out: false)
      expect(SmsService.send_low_balance_alert(customer_without_wallet)).to be false
    end
  end

  describe '.rendered_body' do
    it 'remplace les placeholders {{n:name}} par les valeurs' do
      create(:sms_template, name: "demo", body: "Hello {{0:name}}, montant {{1:amount}}", variables: [])
      expect(SmsService.rendered_body(:demo, name: "Lucas", amount: "12€")).to eq("Hello Lucas, montant 12€")
    end
  end
end
