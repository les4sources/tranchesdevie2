require 'rails_helper'

# Les jobs qui font vivre une Pizza party sans intervention humaine
# (#pizza-parties). Tous les rendez-vous sont calés sur le cut-off de la fournée.
RSpec.describe "Cycle de vie des Pizza parties" do
  include ActiveSupport::Testing::TimeHelpers

  let!(:default_pickup) { create(:pickup_location, name: "Les 4 Sources", default: true) }
  let!(:party_product) { create(:product, :pizza_party) }
  let!(:party_variant) { create(:product_variant, product: party_product, price_cents: 1200) }
  let!(:forfait_product) { create(:product, :pizza_party_forfait) }
  let!(:forfait_variant) { create(:product_variant, product: forfait_product, price_cents: 4000, channel: "admin") }

  around do |example|
    adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = adapter
  end

  def build_request(suffix)
    customer = create(:customer, phone_e164: "+3247080#{suffix}", email: "cycle#{suffix}@example.com")
    create(:party_request, customer: customer)
  end

  describe PartyRequestLifecycleJob do
    it "relance la boulangerie après 48 h de silence, une seule fois" do
      request = build_request("1")
      request.update_columns(created_at: 49.hours.ago)

      expect { described_class.perform_now }.to have_enqueued_mail(PartyRequestMailer, :new_request).at_least(:once)
      expect(request.reload.reminded_at).to be_present

      expect(request.reload.reminded_at).to be_present
    end

    it "ne relance pas une demande déposée il y a deux heures" do
      request = build_request("2")

      described_class.perform_now

      expect(request.reload.reminded_at).to be_nil
    end

    it "clôture au cut-off une demande jamais traitée et prévient le client" do
      request = build_request("3")
      cut_off = PartyRequest.cut_off_for(request.held_on)

      travel_to(cut_off + 1.minute) do
        # `at_least` et non `exactly` : la base de test est partagée et peut
        # porter d'autres demandes, dont ce job s'occupe aussi légitimement.
        expect { described_class.perform_now }
          .to have_enqueued_mail(PartyRequestMailer, :request_expired).at_least(:once)
      end

      expect(request.reload).to be_state_expired
    end

    it "ne clôture pas une demande dont le cut-off n'est pas atteint" do
      request = build_request("4")

      described_class.perform_now

      expect(request.reload).to be_state_pending
    end
  end

  describe PartyPaymentLifecycleJob do
    let(:request) { build_request("5") }
    let(:order) { PartyDecisionService.new(request, decided_by: "Romane").accept }

    def stripe_intent(status:, amount: 0, id: "pi_cycle")
      double(id: id, status: status, amount: amount, client_secret: "#{id}_secret")
    end

    it "sollicite le client 48 h avant le cut-off, pas avant" do
      order
      prompt_at = PartyRequest.payment_prompt_at(request.held_on)

      travel_to(prompt_at - 1.hour) do
        expect { described_class.perform_now }.not_to have_enqueued_mail(PartyRequestMailer, :payment_prompt)
      end

      travel_to(prompt_at + 1.minute) do
        expect { described_class.perform_now }.to have_enqueued_mail(PartyRequestMailer, :payment_prompt)
      end

      expect(order.reload.payment_prompted_at).to be_present
    end

    it "relance 24 h avant l'échéance, une seule fois" do
      order
      reminder_at = order.payment_due_at - 23.hours

      travel_to(reminder_at) do
        expect { described_class.perform_now }.to have_enqueued_mail(PartyRequestMailer, :payment_reminder)
        expect { described_class.perform_now }.not_to have_enqueued_mail(PartyRequestMailer, :payment_reminder)
      end
    end

    it "encaisse à l'échéance un paiement abouti dont le webhook s'est perdu" do
      order.update!(payment_intent_id: "pi_ok")
      allow(Stripe::PaymentIntent).to receive(:retrieve).with("pi_ok")
        .and_return(stripe_intent(status: "succeeded", id: "pi_ok"))

      travel_to(order.payment_due_at + 1.minute) { described_class.perform_now }

      expect(order.reload).to be_paid
    end

    it "laisse vivre un paiement encore en cours (Bancontact) plutôt que de rendre le créneau" do
      order.update!(payment_intent_id: "pi_processing")
      allow(Stripe::PaymentIntent).to receive(:retrieve).with("pi_processing")
        .and_return(stripe_intent(status: "processing", id: "pi_processing"))

      travel_to(order.payment_due_at + 1.minute) { described_class.perform_now }

      expect(order.reload).to be_awaiting_payment
      expect(order.party_event.reload.deleted_at).to be_nil
    end

    it "fait expirer un paiement abandonné : commande annulée, créneau rendu, client prévenu" do
      order.update!(payment_intent_id: "pi_dead")
      allow(Stripe::PaymentIntent).to receive(:retrieve).with("pi_dead")
        .and_return(stripe_intent(status: "canceled", id: "pi_dead"))
      allow(Stripe::PaymentIntent).to receive(:cancel)

      travel_to(order.payment_due_at + 1.minute) do
        expect { described_class.perform_now }.to have_enqueued_mail(PartyRequestMailer, :payment_expired)
      end

      expect(order.reload).to be_cancelled
      expect(order.party_event.reload.deleted_at).to be_present
      expect(PartyEvent.private_slot_available?(request.held_on, "soir")).to be true
    end

    it "fait expirer une réservation jamais payée, sans PaymentIntent du tout" do
      order

      travel_to(order.payment_due_at + 1.minute) { described_class.perform_now }

      expect(order.reload).to be_cancelled
    end

    it "ne touche pas une réservation déjà payée" do
      order.update!(status: :paid)

      travel_to(order.payment_due_at + 1.hour) { described_class.perform_now }

      expect(order.reload).to be_paid
    end
  end
end
