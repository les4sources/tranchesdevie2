require "rails_helper"

# Cochage lieu de retrait ↔ fournée (#148), côté fournée.
RSpec.describe BakeDay, type: :model do
  let!(:default_location) { create(:pickup_location, :default) }
  let(:anhee) { create(:pickup_location, name: "Marché d'Anhée") }

  describe "lieu par défaut à la création" do
    it "coche automatiquement le lieu par défaut sur une nouvelle fournée" do
      bake_day = BakeDay.create!(
        baked_on: Date.current.next_occurring(:tuesday),
        cut_off_at: 2.days.from_now
      )

      expect(bake_day.open_pickup_locations).to eq([ default_location ])
    end

    it "coche le lieu par défaut même si l'admin ne coche rien" do
      bake_day = BakeDay.new(
        baked_on: Date.current.next_occurring(:friday),
        cut_off_at: 2.days.from_now
      )
      bake_day.pickup_location_ids = []
      bake_day.save!

      expect(bake_day.open_pickup_locations).to include(default_location)
    end
  end

  describe "décochage d'un lieu utilisé par des commandes" do
    let(:bake_day) { create(:bake_day, :can_order) }

    before do
      bake_day.pickup_location_ids = [ default_location.id, anhee.id ]
      bake_day.save!
    end

    it "refuse le décochage et indique le nombre de commandes concernées" do
      create(:order, bake_day: bake_day, pickup_location: anhee)
      create(:order, bake_day: bake_day, pickup_location: anhee)

      bake_day.pickup_location_ids = [ default_location.id ]

      expect(bake_day.save).to be false
      expect(bake_day.errors[:pickup_locations].join).to include("Marché d'Anhée")
      expect(bake_day.errors[:pickup_locations].join).to include("2 commandes")
    end

    it "accorde le message au singulier pour une seule commande" do
      create(:order, bake_day: bake_day, pickup_location: anhee)

      bake_day.pickup_location_ids = [ default_location.id ]
      bake_day.save

      expect(bake_day.errors[:pickup_locations].join).to include("1 commande y est rattachée")
    end

    it "ne supprime PAS la jointure quand la validation échoue" do
      create(:order, bake_day: bake_day, pickup_location: anhee)

      bake_day.pickup_location_ids = [ default_location.id ]
      bake_day.save

      expect(bake_day.reload.open_pickup_locations).to include(anhee)
    end

    it "autorise le décochage d'un lieu sans commande" do
      bake_day.pickup_location_ids = [ default_location.id ]

      expect(bake_day.save).to be true
      expect(bake_day.reload.open_pickup_locations).to eq([ default_location ])
    end
  end
end
