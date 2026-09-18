require "rails_helper"

# Pointage d'un encaissement hors ligne sur une Pizza party privée (#289).
#
# Le liquide et le virement ne laissent AUCUNE trace automatique : ce pointage
# est l'encaissement, c'est donc lui qui doit prévenir la compta.
RSpec.describe "Admin — encaissement d'une party privée et compta", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let!(:default_location) { create(:pickup_location, :default) }
  let(:customer) { create(:customer) }
  let(:party_product) { create(:product, :pizza_party) }
  let(:paton) { create(:product_variant, product: party_product, name: "pâton", price_cents: 1_000) }

  let(:private_order) do
    PartyOrderCreationService.new(
      customer: customer,
      party_event: create(:party_event, :private_party, held_on: Date.new(2026, 9, 4)),
      cart_items: [ { "product_variant_id" => paton.id.to_s, "qty" => "6" } ],
      payment_method: "cash"
    ).call
  end

  # L'adapter du projet est Solid Queue : en test, un `deliver_later` reste en
  # base et l'e-mail n'est jamais rendu. On bascule sur l'adapter `:test` pour
  # jouer la file d'envoi à la main (même patron que party_team_notification_spec).
  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = original_adapter
  end

  def point(order, method)
    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
      patch encaissement_admin_order_path(order, method: method)
    end
    order.reload
  end

  it "informe la compta quand le liquide est pointé" do
    order = private_order

    expect { point(order, "cash") }
      .to change { EmailMessage.where(order_id: order.id, kind: :party_accounting_notification).count }.by(1)
  end

  it "informe la compta quand le virement est pointé" do
    order = private_order

    expect { point(order, "transfer") }
      .to change { EmailMessage.where(order_id: order.id, kind: :party_accounting_notification).count }.by(1)
  end

  it "n'informe personne tant que rien n'est pointé (« none »)" do
    order = private_order

    expect { point(order, "none") }
      .not_to change { EmailMessage.where(order_id: order.id, kind: :party_accounting_notification).count }
  end

  it "n'envoie pas un second e-mail quand on repointe" do
    order = private_order
    point(order, "cash")

    expect { point(order, "transfer") }
      .not_to change { EmailMessage.where(order_id: order.id, kind: :party_accounting_notification).count }
  end

  it "ne dit rien à la compta pour une commande de pain encaissée en liquide" do
    bread = create(:order, :ready, customer: customer, bake_day: create(:bake_day), total_cents: 1_500)

    expect { point(bread, "cash") }
      .not_to change { EmailMessage.where(kind: :party_accounting_notification).count }
  end
end
