require "rails_helper"

# Information de la compta à l'encaissement d'une Pizza party privée (#289).
#
# Sœur de send_party_team_notification, avec une différence qui fait tout son
# sens : celle-ci est branchée sur l'ARGENT REÇU, pas sur la réservation.
RSpec.describe OrderNotificationService, ".send_party_accounting_notification" do
  let!(:default_pickup) { create(:pickup_location, name: "Les 4 Sources", default: true) }
  let(:customer) { create(:customer, email: "client@example.com") }

  let(:party_product) { create(:product, :pizza_party) }
  let(:paton) { create(:product_variant, product: party_product, name: "pâton", price_cents: 1_000) }

  let(:public_product) { create(:product, :pizza_party_public) }
  let(:adulte) { create(:product_variant, product: public_product, name: "adulte", price_cents: 1_000) }

  def party_order(event:, variant:, cust: customer)
    PartyOrderCreationService.new(
      customer: cust,
      party_event: event,
      cart_items: [ { "product_variant_id" => variant.id.to_s, "qty" => "4" } ]
    ).call
  end

  let(:private_order) do
    party_order(event: create(:party_event, :private_party, held_on: Date.new(2026, 9, 4)), variant: paton)
  end

  it "informe la compta pour une party privée payée" do
    expect(PartyMailer).to receive(:private_party_paid_for_accounting)
      .with(private_order).and_return(double(deliver_later: true))

    expect(described_class.send_party_accounting_notification(private_order)).to be true
  end

  it "n'envoie rien pour une commande de pain ordinaire" do
    bread_order = create(:order, customer: customer, bake_day: create(:bake_day, :can_order))

    expect(PartyMailer).not_to receive(:private_party_paid_for_accounting)
    expect(described_class.send_party_accounting_notification(bread_order)).to be false
  end

  it "n'envoie rien pour une inscription à une party publique" do
    public_order = party_order(event: create(:party_event, :public_party), variant: adulte)

    expect(PartyMailer).not_to receive(:private_party_paid_for_accounting)
    expect(described_class.send_party_accounting_notification(public_order)).to be false
  end

  it "n'envoie qu'une seule fois : un envoi déjà journalisé bloque le suivant" do
    create(:email_message, customer: nil, order: private_order, kind: :party_accounting_notification)

    expect(PartyMailer).not_to receive(:private_party_paid_for_accounting)
    expect(described_class.send_party_accounting_notification(private_order)).to be false
  end

  it "n'est pas bloquée par la notification d'équipe déjà partie pour la même commande" do
    create(:email_message, customer: nil, order: private_order, kind: :party_team_notification)

    expect(PartyMailer).to receive(:private_party_paid_for_accounting).and_return(double(deliver_later: true))
    expect(described_class.send_party_accounting_notification(private_order)).to be true
  end

  it "part malgré l'opt-out e-mail du client — c'est une notification interne" do
    customer.update!(email_opt_out: true)

    expect(PartyMailer).to receive(:private_party_paid_for_accounting).and_return(double(deliver_later: true))
    expect(described_class.send_party_accounting_notification(private_order)).to be true
  end

  it "part même si le client n'a aucune adresse e-mail" do
    silent = create(:customer, email: nil)
    order = party_order(event: create(:party_event, :private_party), variant: paton, cust: silent)

    expect(PartyMailer).to receive(:private_party_paid_for_accounting).and_return(double(deliver_later: true))
    expect(described_class.send_party_accounting_notification(order)).to be true
  end

  it "capture une erreur d'envoi sans la propager au tunnel de paiement" do
    allow(PartyMailer).to receive(:private_party_paid_for_accounting).and_raise(StandardError, "SMTP down")

    result = nil
    expect { result = described_class.send_party_accounting_notification(private_order) }.not_to raise_error
    expect(result).to be false
  end

  it "ne fait rien sur nil" do
    expect(described_class.send_party_accounting_notification(nil)).to be false
  end
end
