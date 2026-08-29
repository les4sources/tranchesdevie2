require "rails_helper"

# #194 — la fournée est un objet d'organisation, pas de comptabilité : la
# supprimer ne doit jamais faire disparaître une commande.
RSpec.describe Batch do
  let(:bake_day) { create(:bake_day) }

  describe "validations" do
    it "exige un nom" do
      expect(described_class.new(bake_day: bake_day, name: "", position: 1)).not_to be_valid
    end

    it "accepte une fournée nommée et positionnée" do
      expect(described_class.new(bake_day: bake_day, name: "Fournée 1", position: 1)).to be_valid
    end
  end

  describe ".next_default_name / .next_position" do
    it "suit le rang et non le compte, pour qu'une suppression au milieu ne rebaptise rien" do
      create(:batch, bake_day: bake_day, name: "Fournée 1", position: 1)
      second = create(:batch, bake_day: bake_day, name: "Fournée 2", position: 2)

      expect(described_class.next_default_name(bake_day)).to eq("Fournée 3")

      second.destroy!
      expect(described_class.next_position(bake_day)).to eq(2)
    end
  end

  describe "suppression" do
    let(:batch) { create(:batch, bake_day: bake_day) }
    let(:order) { create(:order, :paid, bake_day: bake_day) }
    let!(:item) { create(:order_item, order: order, batch: batch) }

    it "rend les lignes non affectées sans jamais les détruire" do
      expect { batch.destroy! }.not_to change(OrderItem, :count)
      expect(item.reload.batch_id).to be_nil
    end
  end

  describe "renommage" do
    it "persiste le nouveau nom" do
      batch = create(:batch, bake_day: bake_day, name: "Fournée 1")
      batch.update!(name: "Les froments")

      expect(batch.reload.name).to eq("Les froments")
    end
  end
end
