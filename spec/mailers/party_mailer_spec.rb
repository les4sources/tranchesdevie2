require "rails_helper"

RSpec.describe PartyMailer, type: :mailer do
  let!(:default_pickup) { create(:pickup_location, name: "Les 4 Sources", default: true) }
  let(:customer) do
    create(:customer, first_name: "Alix", last_name: "Renard",
                      email: "alix@example.com", phone_e164: "+32470111222")
  end
  let(:party_product) { create(:product, :pizza_party) }
  let(:paton) { create(:product_variant, product: party_product, name: "pâton", price_cents: 1_000) }

  # Un vendredi (wday 5) — jour de boulangerie, cf. BakeDay::COOKING_WDAYS.
  let(:friday) { Date.new(2026, 9, 4) }
  # Un samedi — hors jour de boulangerie.
  let(:saturday) { Date.new(2026, 9, 5) }

  # Le corps encodé est en quoted-printable (les accents et les longues lignes y
  # sont découpés) : on assertionne toujours sur les parties décodées.
  def decoded_body(mail)
    [ mail.html_part&.body&.decoded, mail.text_part&.body&.decoded ].compact.join("\n")
  end

  def build_private_party_order(held_on: friday, slot: :soir, qty: 11, cust: nil)
    event = create(:party_event, :private_party, held_on: held_on, slot: slot)
    PartyOrderCreationService.new(
      customer: cust || customer,
      party_event: event,
      cart_items: [ { "product_variant_id" => paton.id.to_s, "qty" => qty.to_s } ]
    ).call
  end

  describe "#new_private_party" do
    let(:order) { build_private_party_order }

    subject(:mail) { described_class.new_private_party(order) }

    it "part vers la boulangerie avec l'équipe séjours en copie" do
      expect(mail.to).to eq([ "boulangerie@les4sources.be" ])
      expect(mail.cc).to eq([ "sejours@les4sources.be" ])
    end

    it "laisse surcharger les destinataires par variables d'environnement" do
      original_to = ENV["PARTY_NOTIFICATION_TO"]
      original_cc = ENV["PARTY_NOTIFICATION_CC"]
      ENV["PARTY_NOTIFICATION_TO"] = "four@example.com"
      ENV["PARTY_NOTIFICATION_CC"] = "agenda@example.com"

      expect(mail.to).to eq([ "four@example.com" ])
      expect(mail.cc).to eq([ "agenda@example.com" ])
    ensure
      ENV["PARTY_NOTIFICATION_TO"] = original_to
      ENV["PARTY_NOTIFICATION_CC"] = original_cc
    end

    it "identifie la party dans le sujet : date, créneau, nombre de personnes" do
      expect(mail.subject).to eq("Nouvelle Pizza Party privée — vendredi 4 septembre, soir, 11 personnes")
    end

    it "accorde le sujet au singulier pour une seule personne" do
      one = build_private_party_order(qty: 1)

      expect(described_class.new_private_party(one).subject).to include("1 personne")
      expect(described_class.new_private_party(one).subject).not_to include("1 personnes")
    end

    it "détaille la party dans le corps" do
      body = decoded_body(mail)

      expect(body).to include("vendredi 4 septembre 2026")
      expect(body).to include("Soir")
      expect(body).to include("11")
      expect(body).to include("Alix Renard")
      expect(body).to include("alix@example.com")
      expect(body).to include("+32470111222")
      expect(body).to include(order.order_number)
    end

    it "affiche le montant total payé" do
      expect(decoded_body(mail)).to include("110,00")
    end

    it "pointe vers la commande dans l'admin" do
      expect(decoded_body(mail)).to include("/admin/orders/#{order.id}")
    end

    it "signale un four déjà chaud un jour de boulangerie" do
      expect(decoded_body(mail)).to include("Four déjà chaud (jour de boulangerie)")
      expect(decoded_body(mail)).not_to include("chauffer le four")
    end

    it "prévient qu'il faudra chauffer le four hors jour de boulangerie" do
      body = decoded_body(described_class.new_private_party(build_private_party_order(held_on: saturday)))

      expect(body).to include("chauffer le four (~3 h)")
      expect(body).not_to include("Four déjà chaud")
    end

    it "dit explicitement qu'un client sans téléphone est identifié par email" do
      # Un client sans GSM existe : l'admin peut le créer via skip_phone_validation.
      no_phone = create(:customer, first_name: "Sans", last_name: "Tel",
                                   email: "sans@example.com", phone_e164: nil,
                                   skip_phone_validation: true)
      body = decoded_body(described_class.new_private_party(build_private_party_order(cust: no_phone)))

      expect(body).to include("Aucun numéro de téléphone (client identifié par email)")
    end

    it "étiquette le kind et la commande, sans identifier de client destinataire" do
      expect(mail["X-Email-Kind"].value).to eq("party_team_notification")
      expect(mail["X-Order-Id"].value).to eq(order.id.to_s)
      expect(mail["X-Customer-Id"]).to be_nil
    end

    it "ne porte aucun lien de désinscription (ce n'est pas un email client)" do
      expect(decoded_body(mail)).not_to include("/e-mails/preferences/")
    end

    it "se journalise en EmailMessage rattaché à la commande, sans client" do
      expect { mail.deliver_now }.to change(EmailMessage, :count).by(1)

      logged = EmailMessage.last
      expect(logged).to have_attributes(kind: "party_team_notification", order_id: order.id, customer_id: nil)
      expect(logged.to_email).to eq("boulangerie@les4sources.be, sejours@les4sources.be")
    end
  end
end
