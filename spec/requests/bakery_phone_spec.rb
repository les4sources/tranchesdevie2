require "rails_helper"

# #210 — le numéro dédié de la boulangerie dans les coordonnées publiques.
#
# Point de vigilance de l'issue : « Le numéro n'est pas codé en dur à plusieurs
# endroits : il est défini une seule fois et réutilisé. » Ces specs comparent
# donc toujours à `BakeryDetails::PHONE_*`, jamais à un littéral — sauf le spec
# de non-duplication, qui vérifie précisément l'absence de littéraux.
RSpec.describe "Numéro de téléphone de la boulangerie", type: :request do
  let!(:default_pickup) { create(:pickup_location, :default) }

  describe "la définition unique" do
    it "expose les deux formes depuis BakeryDetails" do
      expect(BakeryDetails::PHONE_E164).to eq("+32491240715")
      expect(BakeryDetails::PHONE_DISPLAY).to eq("0491 24 07 15")
    end

    it "n'est écrit en dur nulle part ailleurs dans app/" do
      literals = %w[+32491240715 0491240715]
      offenders = Dir[Rails.root.join("app/**/*.{rb,erb,slim}")].reject do |path|
        path.end_with?("app/models/bakery_details.rb")
      end.select do |path|
        content = File.read(path)
        literals.any? { |literal| content.include?(literal) } ||
          content.include?("0491 24 07 15")
      end

      expect(offenders).to be_empty,
        "numéro codé en dur dans : #{offenders.map { |p| p.sub("#{Rails.root}/", '') }.join(', ')}"
    end

    it "figure dans le bloc d'adresse de la boulangerie" do
      expect(BakeryDetails.address_lines).to include(BakeryDetails::PHONE_DISPLAY)
    end
  end

  shared_examples "affiche le numéro" do |path_name|
    it "affiche le numéro et un lien tel: au format international" do
      get public_send(path_name)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(BakeryDetails::PHONE_DISPLAY)
      expect(response.body).to include(%(href="tel:#{BakeryDetails::PHONE_E164}"))
    end
  end

  describe "le pied de page (présent sur toutes les pages publiques)" do
    include_examples "affiche le numéro", :root_path
  end

  describe "la page À propos" do
    include_examples "affiche le numéro", :a_propos_path
  end

  describe "les conditions générales" do
    include_examples "affiche le numéro", :cgv_path
  end

  describe "la page Vie privée" do
    include_examples "affiche le numéro", :vie_privee_path
  end

  describe "le format" do
    it "affiche le numéro au format belge lisible" do
      get root_path

      expect(response.body).to match(/0491 24 07 15/)
    end

    it "utilise le format international dans le lien, pour que l'appel aboutisse" do
      get root_path

      expect(response.body).to include("tel:+32491240715")
      expect(response.body).not_to include("tel:0491 24 07 15")
    end
  end

  describe "les e-mails" do
    let(:customer) { create(:customer, email: "cliente@example.test") }

    it "porte le numéro dans le pied de page HTML" do
      mail = AuthMailer.otp(customer, "123456")

      expect(mail.html_part&.body.to_s || mail.body.to_s).to include(BakeryDetails::PHONE_DISPLAY)
    end
  end
end
