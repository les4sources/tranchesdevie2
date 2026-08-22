require "rails_helper"

# Reporting produit/catégorie au NET (#153) : la remise de chaque commande est
# répartie au prorata des lignes, si bien que la ventilation produit/catégorie
# se réconcilie EXACTEMENT avec le CA net de la fournée (orders.total_cents).
RSpec.describe Order, ".sales_by_product/category_between (net #153)" do
  let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
  let(:start_date) { Date.new(2026, 5, 1) }
  let(:end_date) { Date.new(2026, 5, 31) }

  let(:pain) { create(:product, name: "Pain complet", internal_category: :boulangerie) }
  let(:brioche) { create(:product, name: "Brioche", internal_category: :boulangerie) }
  let(:cafe) { create(:product, :epicerie, name: "Café") }
  let(:pain_v) { create(:product_variant, product: pain, price_cents: 500) }
  let(:brioche_v) { create(:product_variant, product: brioche, price_cents: 400) }
  let(:cafe_v) { create(:product_variant, product: cafe, price_cents: 300) }

  # Crée une commande finalisée avec un total NET donné (remise = brut − net
  # répartie sur les lignes par le reporting).
  def order_with(total_cents:, lines:, status: :paid)
    order = create(:order, status, bake_day: bake_day, total_cents: total_cents)
    lines.each do |variant, qty|
      create(:order_item, order: order, product_variant: variant, qty: qty,
             unit_price_cents: variant.price_cents)
    end
    order
  end

  describe "réconciliation avec un client remisé" do
    before do
      # Commande remisée : brut = 2*500 + 1*400 = 1400 ; net = 1260 (remise 140).
      order_with(total_cents: 1260, lines: [ [ pain_v, 2 ], [ brioche_v, 1 ] ])
      # Commande sans remise : brut = net = 900 (1*500 pain + 1*400 brioche) + 300 café.
      order_with(total_cents: 1200, lines: [ [ pain_v, 1 ], [ brioche_v, 1 ], [ cafe_v, 1 ] ], status: :ready)
    end

    it "la somme du CA net par produit égale le CA net de la fournée" do
      product_total = Order.sales_by_product_between(start_date, end_date).sum { |e| e[:total_cents] }
      expect(product_total).to eq(Order.revenue_between(start_date, end_date))
      expect(product_total).to eq(1260 + 1200)
    end

    it "la somme du CA net par catégorie égale le CA net de la fournée" do
      category_total = Order.sales_by_internal_category_between(start_date, end_date).sum { |e| e[:total_cents] }
      expect(category_total).to eq(Order.revenue_between(start_date, end_date))
    end

    it "répartit la remise au prorata des lignes brutes (produit)" do
      by_product = Order.sales_by_product_between(start_date, end_date).index_by { |e| e[:product_name] }

      # Commande remisée : remise 140 répartie sur brut 1400 (pain 1000, brioche 400).
      #   pain     : 1000 − round(140*1000/1400)=100 → 900 ; + 500 (2e commande) = 1400
      #   brioche  :  400 − round(140*400/1400)=40  → 360 ; + 400 (2e commande) = 760
      expect(by_product["Pain complet"][:total_cents]).to eq(1400)
      expect(by_product["Brioche"][:total_cents]).to eq(760)
      expect(by_product["Café"][:total_cents]).to eq(300)
    end
  end

  describe "non-régression sans remise" do
    it "le CA net par produit égale le brut quand aucune remise n'est appliquée" do
      order_with(total_cents: 1400, lines: [ [ pain_v, 2 ], [ brioche_v, 1 ] ])

      by_product = Order.sales_by_product_between(start_date, end_date).index_by { |e| e[:product_name] }
      expect(by_product["Pain complet"][:total_cents]).to eq(1000)
      expect(by_product["Brioche"][:total_cents]).to eq(400)
    end
  end

  describe "réconciliation exacte malgré les arrondis" do
    it "absorbe la dérive d'arrondi pour égaler le total net" do
      # Brut = 3*333 = 999 ; net imposé 1000 (arrondis non triviaux).
      three = create(:product_variant, product: pain, price_cents: 333)
      order_with(total_cents: 700, lines: [ [ three, 3 ] ])

      product_total = Order.sales_by_product_between(start_date, end_date).sum { |e| e[:total_cents] }
      expect(product_total).to eq(700)
    end
  end
end
