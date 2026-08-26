require "rails_helper"

# #199 — désactiver un point de retrait sans le supprimer. La distinction se
# joue en un point : ce qu'on PROPOSE au client (`orderable_`) n'est plus ce qui
# est OUVERT sur la fournée (`open_`), et l'historique suit la seconde notion.
RSpec.describe PickupLocation, "drapeau actif" do
  let!(:default_location) { create(:pickup_location, :default) }
  let(:bake_day) { create(:bake_day) }

  it "est actif par défaut — tous les lieux existants le restent après migration" do
    expect(create(:pickup_location, name: "Marché d'Anhée").active?).to be true
  end

  describe "scopes" do
    let!(:champale) { create(:pickup_location, :inactive, name: "Ferme de Champale") }

    it "sépare les actifs des inactifs sans toucher au soft delete" do
      expect(described_class.active).to contain_exactly(default_location)
      expect(described_class.inactive).to contain_exactly(champale)
      expect(described_class.not_deleted).to contain_exactly(default_location, champale)
    end

    it "laisse le soft delete se comporter comme avant" do
      deleted = create(:pickup_location, :deleted, name: "Ancien dépôt")

      expect(described_class.not_deleted).not_to include(deleted)
      expect(described_class.active).to include(deleted) # `active` ne filtre QUE sur `active`
    end
  end

  describe "le lieu par défaut" do
    it "ne peut pas être désactivé" do
      default_location.active = false

      expect(default_location).not_to be_valid
      expect(default_location.errors[:active].join).to include("par défaut")
    end

    it "peut l'être une fois le défaut passé à un autre lieu" do
      other = create(:pickup_location, name: "Marché d'Anhée")

      default_location.update!(default: false)
      other.update!(default: true)

      expect(default_location.update(active: false)).to be true
      expect(default_location.reload.active?).to be false
    end

    it "n'est jamais inactif, donc `default_location` reste utilisable au checkout" do
      expect(described_class.default_location).to eq(default_location)
      expect(described_class.default_location.active?).to be true
    end
  end

  describe "BakeDay#orderable_pickup_locations vs #open_pickup_locations" do
    let!(:champale) { create(:pickup_location, :inactive, name: "Ferme de Champale") }

    before { BakeDayPickupLocation.create!(bake_day: bake_day, pickup_location: champale) }

    it "retire l'inactif des lieux proposables" do
      expect(bake_day.orderable_pickup_locations).to contain_exactly(default_location)
    end

    it "le garde parmi les lieux ouverts — c'est ce qui préserve l'historique" do
      expect(bake_day.open_pickup_locations).to contain_exactly(default_location, champale)
    end
  end

  describe "une commande rattachée à un lieu devenu inactif" do
    let!(:champale) { create(:pickup_location, name: "Ferme de Champale") }

    before { BakeDayPickupLocation.create!(bake_day: bake_day, pickup_location: champale) }

    it "reste valide et garde son lieu après la désactivation" do
      order = create(:order, :paid, bake_day: bake_day, pickup_location: champale)

      champale.update!(active: false)

      expect(order.reload.pickup_location).to eq(champale)
      expect(order).to be_valid
      expect(order.save).to be true
    end
  end
end
