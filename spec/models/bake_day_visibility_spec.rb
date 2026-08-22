require 'rails_helper'

# Fournées réservées aux boulangers : une production posée hors des jours de
# cuisson ordinaires (marché, commande spéciale) ne doit apparaître nulle part
# côté boutique — ni dans le sélecteur du panier, ni dans le bandeau
# « Prochaine fournée » du catalogue.
RSpec.describe BakeDay, "visibilité côté boutique" do
  before { PickupLocation.default_location || create(:pickup_location, :default) }

  # Un samedi (wday 6) n'est pas un jour de cuisson ordinaire, et il tombe avant
  # le prochain mardi : c'est le cas de Romane, une fournée marché plus proche
  # que la fournée suivante.
  let(:marche) do
    create(:bake_day,
           baked_on: Date.current.next_occurring(:saturday),
           cut_off_at: 6.hours.from_now)
  end

  let(:mardi) { create(:bake_day, :tuesday) }

  describe "#open_to_customers?" do
    it "accepte une fournée ordinaire encore ouverte" do
      expect(mardi.open_to_customers?).to be true
    end

    it "refuse une fournée posée un jour hors cuisson, même ouverte" do
      expect(marche.open_to_customers?).to be false
    end

    it "refuse une fournée ordinaire dont la date limite est passée" do
      passee = create(:bake_day, :tuesday, cut_off_at: 1.hour.ago)

      expect(passee.open_to_customers?).to be false
    end
  end

  describe "#visible_to_customers?" do
    it "accepte une fournée ordinaire dont la date limite est passée" do
      passee = create(:bake_day, :friday, cut_off_at: 1.hour.ago)

      # Le calendrier montre ces fournées grisées : visible sans être commandable.
      expect(passee.visible_to_customers?).to be true
      expect(passee.open_to_customers?).to be false
    end

    it "refuse une fournée posée un jour hors cuisson" do
      expect(marche.visible_to_customers?).to be false
    end
  end

  describe ".visible_to_customers" do
    it "exclut la fournée marché, quel que soit son cut-off" do
      marche
      mardi
      passee = create(:bake_day, :friday, cut_off_at: 1.hour.ago)

      visibles = BakeDay.visible_to_customers

      expect(visibles).to include(mardi, passee)
      expect(visibles).not_to include(marche)
    end
  end

  describe ".open_to_customers" do
    it "exclut la fournée marché et garde la fournée ordinaire" do
      marche
      mardi

      expect(BakeDay.open_to_customers).to include(mardi)
      expect(BakeDay.open_to_customers).not_to include(marche)
    end

    it "n'annonce pas la fournée marché comme prochaine fournée, même si elle est la plus proche" do
      marche
      mardi

      expect(marche.baked_on).to be < mardi.baked_on
      expect(BakeDay.open_to_customers.first).to eq(mardi)
    end
  end
end
