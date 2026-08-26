require "rails_helper"

# #207 — « elle a payé, mais dans la compta il n'y a rien qui est calculé par
# rapport à la pizza party ».
#
# Cause : une réservation en ligne crée sa commande avec `bake_day: nil` (par
# design — une party est datée par son événement), alors que le calcul des
# revenus partait de `bake_day.orders`. Les deux ne se rejoignaient jamais.
#
# Correction retenue : l'assiette comptable du jour est désormais l'union des
# commandes rattachées à la fournée ET des commandes party que cette fournée
# prépare, via `PartyEvent.prepared_by` — la même réciproque que le tableau de
# bord utilise déjà pour annoncer les pâtons.
RSpec.describe "Rattachement comptable des pizza parties" do
  let(:friday) { Date.new(2026, 9, 4) }
  let(:tuesday) { Date.new(2026, 9, 1) }
  let(:saturday) { Date.new(2026, 9, 5) }

  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:friday_bake) { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }

  let(:party_product) { create(:product, :pizza_party, name: "Pizza party privée") }
  let!(:paton) { create(:product_variant, product: party_product, name: "1 boule", price_cents: 500, flour_quantity: 200, channel: "store") }
  let(:forfait_product) { create(:product, :pizza_party_forfait, name: "Forfait Pizza party privée") }
  let!(:forfait) { create(:product_variant, product: forfait_product, name: "forfait", price_cents: 4_000, channel: "store") }

  let(:customer) { create(:customer, first_name: "Fabienne", last_name: "Renard") }
  let(:artisan) { create(:artisan, name: "Romane") }

  before do
    create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
    create(:variant_cost_price, product_variant: paton, amount_cents: 26, active_from: friday - 60)
    create(:artisan_revenue_share, artisan: artisan, percent: 100, active_from: Date.new(2026, 1, 1))
    create(:bake_day_artisan, bake_day: friday_bake, artisan: artisan)
  end

  # Réservation EN LIGNE : commande avec bake_day nil, rattachée à l'événement.
  # C'est la commande TV-20260730-0001 de production : 11 pâtons + forfait, 95 €.
  def online_party(held_on: friday, slot: :soir, persons: 11, with_forfait: true, status: :paid)
    event = create(:party_event, :private_party, held_on: held_on, slot: slot)
    total = persons * 500 + (with_forfait ? 4_000 : 0)
    order = create(:order, status, customer: customer, bake_day: nil, party_event: event,
                                   source: :party, total_cents: total)
    create(:order_item, order: order, product_variant: paton, qty: persons, unit_price_cents: 500)
    create(:order_item, order: order, product_variant: forfait, qty: 1, unit_price_cents: 4_000) if with_forfait
    [ event, order ]
  end

  # Party ENCODÉE À LA MAIN sur une fournée : le cas des 17 de production.
  def manual_party(bake_day:, persons: 8)
    order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: persons * 500)
    create(:order_item, order: order, product_variant: paton, qty: persons, unit_price_cents: 500)
    order
  end

  def report(from = friday, to = friday)
    BakerRevenueService.new(start_date: from, end_date: to).call
  end

  describe "la party du 4 septembre (reproduction du bug)" do
    it "entre désormais dans les revenus, à hauteur du barème privé" do
      _, order = online_party(persons: 11, with_forfait: true)

      expect(order.bake_day_id).to be_nil, "la commande n'a toujours pas de fournée — c'est le point"
      expect(order.total_cents).to eq(9_500)

      day = report.days.first

      expect(day.party_persons).to eq(11)
      expect(day.party_revenue_cents).to eq(9_500)
      expect(day.party_bakers_cents).to be > 0
      expect(day.party_four_sources_cents).to be > 0
    end

    it "l'ajoute au CA du jour, pas seulement au split — sinon la marge pain se creuserait" do
      before_party = report.days.first
      online_party(persons: 11, with_forfait: true)
      after_party = report.days.first

      expect(after_party.revenue_cents - before_party.revenue_cents).to eq(9_500)
      # La marge « pain » ne bouge pas d'un centime : la party est isolée.
      non_party_before = before_party.gross_margin_cents - before_party.party_bakers_cents - before_party.party_four_sources_cents
      non_party_after = after_party.gross_margin_cents - after_party.party_bakers_cents - after_party.party_four_sources_cents
      expect(non_party_after).to eq(non_party_before)
    end

    it "la compte sur UN SEUL jour" do
      create(:bake_day, baked_on: tuesday, cut_off_at: tuesday - 2.days)
      online_party(held_on: friday, slot: :soir, persons: 11)

      days = report(tuesday, friday).days
      counted = days.select { |day| day.party_persons.positive? }

      expect(counted.size).to eq(1)
      expect(counted.first.date).to eq(friday)
    end

    it "apparaît dans la feuille compta du jour" do
      online_party(persons: 11, with_forfait: true)

      sheet = BakeDaySheetService.call(friday_bake)

      expect(sheet.day).to be_present
      expect(sheet.day.party_persons).to eq(11)
      expect(sheet.day.party_revenue_cents).to eq(9_500)
    end
  end

  describe "une party de MIDI, préparée la veille" do
    it "est comptée une seule fois, sur le jour de préparation" do
      create(:bake_day, baked_on: tuesday, cut_off_at: tuesday - 2.days)
      # Party le samedi midi : préparée par la fournée du vendredi.
      online_party(held_on: saturday, slot: :midi, persons: 6, with_forfait: false)

      days = report(tuesday, saturday).days
      counted = days.select { |day| day.party_persons.positive? }

      expect(counted.size).to eq(1)
      expect(counted.first.date).to eq(friday)
      expect(counted.first.party_persons).to eq(6)
    end
  end

  describe "aucun double comptage" do
    it "une party déjà rattachée à une fournée garde exactement son traitement" do
      manual = manual_party(bake_day: friday_bake, persons: 8)

      day = report.days.first

      expect(day.party_persons).to eq(8)
      expect(day.party_revenue_cents).to eq(4_000)
      expect(day.revenue_cents).to eq(manual.total_cents)
    end

    it "une commande portant À LA FOIS une fournée et un événement n'est comptée qu'une fois" do
      event = create(:party_event, :private_party, held_on: friday, slot: :soir)
      order = create(:order, :paid, customer: customer, bake_day: friday_bake, party_event: event,
                                    source: :party, total_cents: 8 * 500)
      create(:order_item, order: order, product_variant: paton, qty: 8, unit_price_cents: 500)

      day = report.days.first

      expect(day.party_persons).to eq(8)
      expect(day.party_revenue_cents).to eq(4_000)
      expect(day.revenue_cents).to eq(4_000)
    end
  end

  describe "non-régression" do
    it "une période sans party réservée en ligne est inchangée au centime" do
      bread = create(:product, :bread, name: "Pain froment")
      variant = create(:product_variant, product: bread, name: "Grand", flour_quantity: 800, price_cents: 650)
      order = create(:order, :paid, customer: customer, bake_day: friday_bake, total_cents: 10 * 650)
      create(:order_item, order: order, product_variant: variant, qty: 10, unit_price_cents: 650)

      day = report.days.first

      expect(day.revenue_cents).to eq(6_500)
      expect(day.party_persons).to eq(0)
      expect(day.party_revenue_cents).to eq(0)
      expect(day.party_bakers_cents).to eq(0)
      expect(day.party_four_sources_cents).to eq(0)
    end

    it "une réservation NON payée ne contribue à rien" do
      online_party(persons: 11, status: :unpaid)

      day = report.days.first

      expect(day.party_persons).to eq(0)
      expect(day.party_revenue_cents).to eq(0)
      expect(day.revenue_cents).to eq(0)
    end

    it "une réservation annulée ne contribue à rien" do
      online_party(persons: 11, status: :cancelled)

      expect(report.days.first.party_persons).to eq(0)
    end
  end

  # Le critère 10 : les parties PUBLIQUES sont-elles concernées ?
  describe "parties publiques" do
    let(:public_product) { create(:product, :pizza_party_public, name: "Party publique") }
    let!(:adulte) { create(:product_variant, product: public_product, name: "adulte", price_cents: 1_000, party_four_sources_base_cents: 300, flour_quantity: 200) }

    before { create(:variant_cost_price, product_variant: adulte, amount_cents: 26, active_from: friday - 60) }

    it "sont concernées par le MÊME bug, et corrigées de la même façon" do
      event = create(:party_event, :public_party, held_on: friday)
      order = create(:order, :paid, customer: customer, bake_day: nil, party_event: event,
                                    source: :party, total_cents: 5 * 1_000)
      create(:order_item, order: order, product_variant: adulte, qty: 5, unit_price_cents: 1_000)

      day = report.days.first

      expect(order.bake_day_id).to be_nil
      expect(day.public_party_persons).to eq(5)
      expect(day.public_party_revenue_cents).to eq(5_000)
      expect(day.revenue_cents).to eq(5_000)
    end
  end

  # Le filet demandé par le critère 9 : aucune commande de party finalisée ne
  # doit échapper au calcul — et la spec NOMME celles qui échapperaient.
  describe "filet de couverture" do
    it "ne laisse aucune commande de party finalisée hors des revenus" do
      create(:bake_day, baked_on: tuesday, cut_off_at: tuesday - 2.days)
      online_party(held_on: friday, slot: :soir, persons: 11)
      online_party(held_on: saturday, slot: :midi, persons: 6, with_forfait: false)
      manual_party(bake_day: friday_bake, persons: 8)

      days = report(tuesday, saturday).days
      counted_ids = days.flat_map { |day| BakerRevenueService.new(start_date: day.date, end_date: day.date)
                                                            .send(:day_accounted_orders, day.bake_day)
                                                            .map(&:id) }.to_set

      party_order_ids = Order.completed
                             .where(id: OrderItem.joins(product_variant: :product)
                                                 .where(products: { pizza_party_role: [ Product.pizza_party_roles[:party],
                                                                                        Product.pizza_party_roles[:public_party] ] })
                                                 .select(:order_id))
                             .pluck(:id)

      missing = party_order_ids - counted_ids.to_a

      expect(missing).to be_empty,
        "commandes de party finalisées absentes des revenus : #{Order.where(id: missing).pluck(:order_number).join(', ')}"
    end
  end
end
