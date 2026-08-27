require "rails_helper"

# Rattachement comptable des pizza parties PUBLIQUES.
#
# Les parties PRIVÉES sont rattachées à la fournée qui pétrit leurs pâtons via
# `PartyEvent.preparation_bake_day` / `.prepared_by` : la fournée du soir même
# si elle existe, SINON la dernière fournée qui précède. Une party privée tenue
# un jour sans fournée reste donc comptée.
#
# Les parties PUBLIQUES n'avaient pas ce filet : `BakeDayPartyOrders` ne les
# reconnaissait que sur une égalité stricte `held_on = baked_on`. Or l'admin
# choisit la date d'une party publique dans un champ date libre, sans contrainte
# de jour de cuisson : une party publique posée un jour sans fournée sortait
# INTÉGRALEMENT des revenus des boulangers — CA, part 4 Sources et part
# boulangers disparaissaient d'un coup, sans le moindre avertissement.
#
# Ces specs verrouillent la symétrie : privé et public suivent désormais la même
# règle de rattachement, et une party publique ne peut plus s'évaporer.
RSpec.describe "Rattachement comptable des pizza parties publiques" do
  let(:friday) { Date.new(2026, 9, 4) }
  let(:saturday) { Date.new(2026, 9, 5) }
  let(:tuesday) { Date.new(2026, 9, 8) }

  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:friday_bake) { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }

  let(:public_product) { create(:product, :pizza_party_public, name: "Pizza party publique") }
  let!(:adulte) do
    create(:product_variant, product: public_product, name: "adulte", price_cents: 1_000,
                             party_four_sources_base_cents: 300, flour_quantity: 200)
  end

  let(:customer) { create(:customer) }
  let(:artisan) { create(:artisan, name: "Romane") }

  before do
    create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
    create(:variant_cost_price, product_variant: adulte, amount_cents: 26, active_from: friday - 60)
    create(:artisan_revenue_share, artisan: artisan, percent: 100, active_from: Date.new(2026, 1, 1))
    create(:bake_day_artisan, bake_day: friday_bake, artisan: artisan)
  end

  # Inscription EN LIGNE à une party publique : commande sans fournée, rattachée
  # à l'événement (c'est le seul chemin — PublicPartyRegistrationService).
  def public_party(held_on:, persons: 5)
    event = create(:party_event, :public_party, held_on: held_on)
    order = create(:order, :paid, customer: customer, bake_day: nil, party_event: event,
                                  source: :party, total_cents: persons * 1_000)
    create(:order_item, order: order, product_variant: adulte, qty: persons, unit_price_cents: 1_000)
    [ event, order ]
  end

  def report(from, to)
    BakerRevenueService.new(start_date: from, end_date: to).call
  end

  describe "une party publique tenue un jour SANS fournée" do
    it "est comptée par la fournée qui la précède, au lieu de disparaître" do
      _, order = public_party(held_on: saturday, persons: 5)

      expect(order.bake_day_id).to be_nil
      expect(BakeDay.exists?(baked_on: saturday)).to be(false), "le samedi ne doit pas être un jour de cuisson"

      result = report(friday, saturday)

      expect(result.total_public_party_persons).to eq(5)
      expect(result.total_public_party_revenue_cents).to eq(5_000)
      expect(result.total_public_party_bakers_cents).to be > 0
      expect(result.total_public_party_four_sources_cents).to be > 0
    end

    it "verse bien sa part au pool des boulangers" do
      before_party = report(friday, saturday).baker_pool_cents
      public_party(held_on: saturday, persons: 5)
      after_party = report(friday, saturday)

      expect(after_party.baker_pool_cents - before_party).to eq(after_party.total_public_party_bakers_cents)
      expect(after_party.total_public_party_bakers_cents).to be > 0
    end

    it "n'est comptée que sur UN seul jour" do
      create(:bake_day, baked_on: tuesday, cut_off_at: tuesday - 2.days)
      public_party(held_on: saturday, persons: 5)

      counted = report(friday, tuesday).days.select { |day| day.public_party_persons.positive? }

      expect(counted.size).to eq(1)
      expect(counted.first.date).to eq(friday)
    end

    it "revient à la fournée la plus proche AVANT elle, pas à une plus ancienne" do
      earlier = Date.new(2026, 9, 1)
      create(:bake_day, baked_on: earlier, cut_off_at: earlier - 2.days)
      public_party(held_on: saturday, persons: 5)

      counted = report(earlier, saturday).days.select { |day| day.public_party_persons.positive? }

      expect(counted.map(&:date)).to eq([ friday ])
    end
  end

  describe "non-régression" do
    it "une party publique tenue LE jour de la fournée reste comptée une fois" do
      public_party(held_on: friday, persons: 5)

      result = report(friday, friday)

      expect(result.total_public_party_persons).to eq(5)
      expect(result.total_public_party_revenue_cents).to eq(5_000)
      expect(result.days.count { |day| day.public_party_persons.positive? }).to eq(1)
    end

    it "une party publique tenue APRÈS la fournée suivante revient à cette dernière" do
      create(:bake_day, baked_on: tuesday, cut_off_at: tuesday - 2.days)
      wednesday = Date.new(2026, 9, 9)
      public_party(held_on: wednesday, persons: 5)

      counted = report(friday, wednesday).days.select { |day| day.public_party_persons.positive? }

      expect(counted.map(&:date)).to eq([ tuesday ])
    end

    it "une inscription non payée ne contribue à rien" do
      event = create(:party_event, :public_party, held_on: saturday)
      order = create(:order, :unpaid, customer: customer, bake_day: nil, party_event: event,
                                      source: :party, total_cents: 5_000)
      create(:order_item, order: order, product_variant: adulte, qty: 5, unit_price_cents: 1_000)

      result = report(friday, saturday)

      expect(result.total_public_party_persons).to eq(0)
      expect(result.total_public_party_revenue_cents).to eq(0)
    end

    it "une party publique antérieure à TOUTE fournée n'est rattachée à aucune" do
      public_party(held_on: friday - 1, persons: 5)

      expect(report(friday - 7, friday).total_public_party_persons).to eq(0)
    end
  end

  describe "symétrie avec les parties privées" do
    it "public et privé suivent la même règle de rattachement un jour sans fournée" do
      public_party(held_on: saturday, persons: 5)

      private_product = create(:product, :pizza_party, name: "Pizza party privée")
      paton = create(:product_variant, product: private_product, name: "1 boule",
                                       price_cents: 500, flour_quantity: 200)
      create(:variant_cost_price, product_variant: paton, amount_cents: 26, active_from: friday - 60)
      private_event = create(:party_event, :private_party, held_on: saturday, slot: :midi)
      private_order = create(:order, :paid, customer: customer, bake_day: nil, party_event: private_event,
                                            source: :party, total_cents: 4_000)
      create(:order_item, order: private_order, product_variant: paton, qty: 8, unit_price_cents: 500)

      day = report(friday, saturday).days.first

      expect(day.party_persons).to eq(8), "la party privée du samedi doit être comptée"
      expect(day.public_party_persons).to eq(5), "la party publique du samedi doit l'être aussi"
    end
  end
end
