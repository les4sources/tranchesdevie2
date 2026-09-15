require 'rails_helper'

# Les e-mails du parcours Pizza party (#pizza-parties).
#
# Ils sont TRANSACTIONNELS : un client désabonné qui réserve une party doit
# recevoir son lien de règlement, sans quoi sa réservation expire sans qu'il ait
# jamais été prévenu.
RSpec.describe PartyRequestMailer do
  let!(:default_pickup) { create(:pickup_location, name: "Les 4 Sources", default: true) }
  let!(:party_product) { create(:product, :pizza_party) }
  let!(:party_variant) { create(:product_variant, product: party_product, price_cents: 1200) }
  let!(:forfait_product) { create(:product, :pizza_party_forfait) }
  let!(:forfait_variant) { create(:product_variant, product: forfait_product, price_cents: 4000, channel: "admin") }

  let(:customer) do
    create(:customer, first_name: "Camille", last_name: "Dupont",
                      phone_e164: "+32470303030", email: "camille@example.com")
  end
  let(:party_request) do
    create(:party_request, customer: customer,
                           customer_note: "Les 40 ans de Claire, arrivée vers 18h.")
  end

  describe "#new_request (équipe)" do
    subject(:mail) { described_class.new_request(party_request) }

    it "part aux deux adresses de l'équipe" do
      expect(mail.to).to eq([ PartyMailer.notification_to ])
      expect(mail.cc).to eq([ PartyMailer.notification_cc ])
    end

    it "porte tout ce qu'il faut pour décider, champ par champ" do
      body = mail.body.encoded

      expect(mail.subject).to include("Demande de Pizza party privée")
      expect(body).to include(I18n.l(party_request.held_on, format: :long_with_day))
      expect(body).to include(party_request.slot_label)
      expect(body).to include("Camille Dupont")
      expect(body).to include("camille@example.com")
      expect(body).to include("+32470303030")
      expect(body).to include("Les 40 ans de Claire")
      expect(body).to include("12,00") # tarif figé par personne
      expect(body).to include("40,00") # forfait
    end

    it "n'annonce aucun nombre de participants : il n'est pas encore connu" do
      expect(mail.body.encoded).not_to match(/\d+ personnes? annoncées?/)
    end

    it "porte deux URL de décision signées DISTINCTES" do
      body = mail.body.encoded
      urls = body.scan(%r{/admin/parties/decision\?[^"'\s]+}).map { |u| CGI.unescapeHTML(u) }

      expect(urls.size).to be >= 2
      expect(urls.any? { |u| u.include?("decision=accept") }).to be true
      expect(urls.any? { |u| u.include?("decision=refuse") }).to be true
    end

    it "signe ses jetons pour le seul usage « décision »" do
      token = mail.body.encoded[/token=([^&"'\s]+)/, 1]
      token = CGI.unescape(token)

      expect(PartyRequest.find_signed(token, purpose: :party_decision)).to eq(party_request)
      expect(PartyRequest.find_signed(token, purpose: :email_unsubscribe)).to be_nil
    end
  end

  describe "e-mails transactionnels" do
    let(:opted_out) do
      create(:customer, first_name: "Jean", phone_e164: "+32470303031",
                        email: "jean@example.com", email_opt_out: true)
    end
    let(:request_opted_out) { create(:party_request, customer: opted_out) }

    it "part malgré un désabonnement — accusé de réception" do
      mail = described_class.received(request_opted_out)
      expect(mail.to).to eq([ "jean@example.com" ])
    end

    it "part malgré un désabonnement — refus avec motif" do
      request_opted_out.update!(state: :refused, decision_reason: "Four déjà pris ce soir-là.")

      mail = described_class.refused(request_opted_out)

      expect(mail.to).to eq([ "jean@example.com" ])
      expect(mail.body.encoded).to include("Four déjà pris ce soir-là.")
    end
  end

  describe "#accepted" do
    it "annonce le rendez-vous de paiement quand la validation est en avance" do
      order = PartyDecisionService.new(party_request, decided_by: "Romane").accept
      mail = described_class.accepted(party_request.reload)

      expect(mail.body.encoded).to include("Nous t'écrirons le")
      expect(mail.body.encoded).to include(order.public_token)
    end
  end
end
