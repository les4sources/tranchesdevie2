require "rails_helper"

RSpec.describe PickupLocation, type: :model do
  describe "lieu par défaut" do
    it "n'autorise qu'un seul lieu par défaut" do
      create(:pickup_location, :default)

      other = build(:pickup_location, name: "Marché d'Anhée", default: true)

      expect(other).not_to be_valid
      expect(other.errors[:default]).to be_present
    end

    it "autorise autant de lieux non-défaut que voulu" do
      create(:pickup_location, :default)

      expect(build(:pickup_location, name: "Marché d'Anhée")).to be_valid
      expect(build(:pickup_location, name: "Marché de Dinant")).to be_valid
    end

    it "expose le lieu par défaut via .default_location" do
      default = create(:pickup_location, :default)
      create(:pickup_location, name: "Marché d'Anhée")

      expect(described_class.default_location).to eq(default)
    end

    it "ignore un lieu par défaut supprimé" do
      create(:pickup_location, :default, :deleted)

      expect(described_class.default_location).to be_nil
    end
  end

  describe "soft delete" do
    it "retire le lieu des sélecteurs sans casser les commandes qui le référencent" do
      location = create(:pickup_location, name: "Marché d'Anhée")
      bake_day = create(:bake_day)
      bake_day.pickup_location_ids = bake_day.pickup_location_ids + [ location.id ]
      bake_day.save!
      order = create(:order, bake_day: bake_day, pickup_location: location)

      location.soft_delete!

      expect(described_class.not_deleted).not_to include(location)
      # La commande reste lisible et affiche toujours le nom du lieu.
      expect(order.reload.pickup_location.name).to eq("Marché d'Anhée")
    end
  end

  describe "ordre d'affichage" do
    it "trie par position puis par nom" do
      create(:pickup_location, :default, position: 0)
      anhee = create(:pickup_location, name: "Marché d'Anhée", position: 2)
      dinant = create(:pickup_location, name: "Marché de Dinant", position: 1)

      expect(described_class.not_deleted.ordered.map(&:name))
        .to eq([ "Les 4 Sources", dinant.name, anhee.name ])
    end
  end

  describe "cochage des fournées depuis la fiche du lieu" do
    let!(:default_location) { create(:pickup_location, :default) }
    let(:location) { create(:pickup_location, name: "Marché d'Anhée") }
    let(:bake_day) { create(:bake_day, :can_order) }

    it "ouvre le lieu sur les fournées cochées" do
      location.update!(bake_day_ids: [ bake_day.id ])

      expect(bake_day.reload.open_pickup_locations).to include(location)
    end

    it "refuse de fermer une fournée dont des commandes utilisent ce lieu" do
      location.update!(bake_day_ids: [ bake_day.id ])
      create(:order, bake_day: bake_day, pickup_location: location)

      location.bake_day_ids = []

      expect(location.save).to be false
      expect(location.errors[:bake_days].join).to include("1 commande")
      # La jointure n'a PAS été supprimée : la validation a bien bloqué en amont.
      expect(bake_day.reload.open_pickup_locations).to include(location)
    end

    it "conserve le rattachement aux fournées passées, absentes du formulaire" do
      past_bake_day = create(:bake_day, :past)
      BakeDayPickupLocation.create!(bake_day: past_bake_day, pickup_location: location)

      # Le formulaire ne liste que les fournées à venir : il ne renvoie donc
      # jamais l'id d'une fournée passée. Elle ne doit pas être détachée pour autant.
      location.update!(bake_day_ids: [ bake_day.id ])

      expect(past_bake_day.reload.open_pickup_locations).to include(location)
    end
  end
end
