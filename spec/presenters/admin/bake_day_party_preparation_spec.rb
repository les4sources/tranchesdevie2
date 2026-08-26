require "rails_helper"

# Rattachement des pâtons de party à la bonne fournée (#170).
RSpec.describe Admin::BakeDayDashboard, "parties à préparer" do
  let(:tuesday)  { Date.new(2026, 9, 1) }
  let(:friday)   { Date.new(2026, 9, 4) }
  let(:saturday) { Date.new(2026, 9, 5) }

  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:tuesday_bake) { create(:bake_day, baked_on: tuesday, cut_off_at: tuesday - 2.days) }
  let!(:friday_bake)  { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }

  let(:customer) { create(:customer, first_name: "Alix", last_name: "Renard") }

  # Produit party : catégorie dough_balls (les pâtons), rôle :party.
  let(:party_product) do
    create(:product, :pizza_party, category: :dough_balls, name: "Pizza party privée")
  end
  let(:paton) do
    create(:product_variant, product: party_product, name: "une boule",
                             price_cents: 500, flour_quantity: 200)
  end

  # Une commande :pending ne compte pas en production (elle n'est pas confirmée) :
  # les parties réservées ici sont payées, comme celles que voient les boulangers.
  def book_party(held_on:, slot:, qty: 11, status: :paid)
    event = create(:party_event, :private_party, held_on: held_on, slot: slot)
    order = PartyOrderCreationService.new(
      customer: customer, party_event: event,
      cart_items: [ { "product_variant_id" => paton.id.to_s, "qty" => qty.to_s } ]
    ).call
    order.update!(status: status)
    order
  end

  def dashboard_for(bake_day)
    described_class.new(bake_day)
  end

  describe "affectation" do
    it "rattache une party du SOIR à la fournée du jour même" do
      book_party(held_on: friday, slot: :soir)

      expect(dashboard_for(friday_bake).parties_to_prepare.size).to eq(1)
      expect(dashboard_for(tuesday_bake).parties_to_prepare).to be_empty
    end

    it "rattache une party de MIDI à la fournée précédente, plus à celle du jour" do
      book_party(held_on: friday, slot: :midi)

      expect(dashboard_for(tuesday_bake).parties_to_prepare.size).to eq(1)
      expect(dashboard_for(friday_bake).parties_to_prepare).to be_empty
    end

    it "rattache une party du samedi à la fournée du vendredi" do
      book_party(held_on: saturday, slot: :soir)

      expect(dashboard_for(friday_bake).parties_to_prepare.size).to eq(1)
      expect(dashboard_for(tuesday_bake).parties_to_prepare).to be_empty
    end

    it "ignore une party dont la commande est annulée" do
      book_party(held_on: friday, slot: :soir, status: :cancelled)

      expect(dashboard_for(friday_bake).parties_to_prepare).to be_empty
      expect(dashboard_for(tuesday_bake).parties_to_prepare).to be_empty
    end
  end

  describe "ce que le bloc annonce" do
    it "porte date, créneau, nombre de pâtons et client" do
      book_party(held_on: friday, slot: :soir, qty: 11)

      party = dashboard_for(friday_bake).parties_to_prepare.first

      expect(party[:held_on]).to eq(friday)
      expect(party[:slot_label]).to eq("Soir")
      expect(party[:paton_count]).to eq(11)
      expect(party[:customer_name]).to eq("Alix Renard")
      expect(party[:same_day]).to be true
    end

    it "distingue une party qui n'a pas lieu le jour même" do
      book_party(held_on: saturday, slot: :soir)

      party = dashboard_for(friday_bake).parties_to_prepare.first

      expect(party[:same_day]).to be false
      expect(party[:held_on]).to eq(saturday)
    end
  end

  describe "quantités de production" do
    it "compte la farine des pâtons sur la fournée d'affectation" do
      book_party(held_on: saturday, slot: :soir, qty: 10)

      # 10 pâtons × 200 g de farine, portés par la fournée du vendredi.
      expect(dashboard_for(friday_bake).total_flour_quantity).to eq(2_000)
      expect(dashboard_for(tuesday_bake).total_flour_quantity).to eq(0)
    end

    it "n'inclut pas les pâtons d'une party de midi dans la fournée du jour même" do
      book_party(held_on: friday, slot: :midi, qty: 10)

      expect(dashboard_for(friday_bake).total_flour_quantity).to eq(0)
      expect(dashboard_for(tuesday_bake).total_flour_quantity).to eq(2_000)
    end

    it "laisse une fournée sans party strictement inchangée" do
      expect(dashboard_for(friday_bake).parties_to_prepare).to be_empty
      expect(dashboard_for(friday_bake).total_flour_quantity).to eq(0)
      expect(dashboard_for(friday_bake).breads_mold_requirements.values.sum).to eq(0)
    end
  end

  describe "parties publiques — rattachées au jour même" do
    let(:public_product) { create(:product, :pizza_party_public, category: :dough_balls) }
    let(:adulte) do
      create(:product_variant, product: public_product, name: "adulte",
                               price_cents: 1_000, flour_quantity: 200)
    end

    it "reste rattachée au jour même, pas à la fournée précédente" do
      event = create(:party_event, :public_party, held_on: friday)
      PartyOrderCreationService.new(
        customer: customer, party_event: event,
        cart_items: [ { "product_variant_id" => adulte.id.to_s, "qty" => "5" } ]
      ).call.update!(status: :paid)

      # Comptée en production le jour même…
      expect(dashboard_for(friday_bake).total_flour_quantity).to eq(1_000)
      expect(dashboard_for(tuesday_bake).total_flour_quantity).to eq(0)
      # …et depuis #202, listée dans le bloc du jour même — elle demande elle
      # aussi des pâtons — mais JAMAIS sur la fournée précédente.
      friday_entries = dashboard_for(friday_bake).parties_to_prepare
      expect(friday_entries.size).to eq(1)
      expect(friday_entries.first[:private]).to be false
      expect(friday_entries.first[:kind_label]).to eq("Party publique")
      expect(dashboard_for(tuesday_bake).parties_to_prepare).to be_empty
    end
  end
end
