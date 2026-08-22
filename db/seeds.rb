# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Products and variants according to PRD

# Category: Breads
breads = [
  {
    name: "Pain d'épeautre",
    description: "Pain d'épeautre",
    position: 1,
    variants: [
      { name: "1 kg", price_cents: 550 },
      { name: "600 g", price_cents: 350 }
    ]
  },
  {
    name: "Pain au froment",
    description: "Pain de froment",
    position: 2,
    variants: [
      { name: "1 kg", price_cents: 450 },
      { name: "600 g", price_cents: 300 }
    ]
  },
  {
    name: "Pain aux céréales anciennes",
    description: "Pain aux céréales anciennes",
    position: 3,
    variants: [
      { name: "600 g", price_cents: 550 }
    ]
  },
  {
    name: "Pain aux noix",
    description: "Pain aux noix",
    position: 4,
    variants: [
      { name: "1 kg", price_cents: 550 },
      { name: "600 g", price_cents: 400 }
    ]
  },
  {
    name: "Pain aux graines",
    description: "Pain aux graines",
    position: 5,
    variants: [
      { name: "1 kg", price_cents: 550 },
      { name: "600 g", price_cents: 400 }
    ]
  },
  {
    name: "Pain aux noix/figues",
    description: "Pain noix/figues",
    position: 6,
    variants: [
      { name: "600 g", price_cents: 400 }
    ]
  },
  {
    name: "Pain au chocolat/sucre",
    description: "Pain chocolat/sucre",
    position: 7,
    variants: [
      { name: "600 g", price_cents: 400 }
    ]
  }
]

# Category: Dough balls
# Le produit « Pizza party privée » et son forfait sont gérés plus bas dans un
# bloc dédié (#68) : ils demandent un rôle (pizza_party_role) et un rename
# idempotent que la boucle générique ci-dessous ne sait pas faire.
dough_balls = [
  {
    name: "Boule de pâte à pizza à emporter",
    description: "Boule de pâte à pizza à emporter",
    position: 1,
    variants: [
      { name: "une boule", price_cents: 200 }
    ]
  }
]

# Create products
breads.each do |product_data|
  product = Product.find_or_create_by!(name: product_data[:name]) do |p|
    p.description = product_data[:description]
    p.category = :breads
    p.position = product_data[:position]
    p.active = true
  end

  product_data[:variants].each do |variant_data|
    ProductVariant.find_or_create_by!(product: product, name: variant_data[:name]) do |v|
      v.price_cents = variant_data[:price_cents]
      v.active = true
    end
  end
end

dough_balls.each do |product_data|
  product = Product.find_or_create_by!(name: product_data[:name]) do |p|
    p.description = product_data[:description]
    p.category = :dough_balls
    p.position = product_data[:position]
    p.active = true
  end

  product_data[:variants].each do |variant_data|
    ProductVariant.find_or_create_by!(product: product, name: variant_data[:name]) do |v|
      v.price_cents = variant_data[:price_cents]
      v.active = true
    end
  end
end

# --- Pizza party privée (#68) -----------------------------------------------
# Le produit « party » (1 boule de pâte / personne) et son « forfait » 40 €.
#
# Le produit party a été renommé : on le retrouve par son NOUVEAU nom OU son
# ANCIEN nom (rename historique) pour rester idempotent et ne jamais créer de
# doublon. Le forfait est un produit `channel: "admin"` (donc absent du
# catalogue store et non ajoutable directement) dont l'UNIQUE variante reste en
# `channel: "store"` : ainsi elle survit au filtre panier
# `remove_unavailable_cart_items!` (qui teste la variante, pas le produit), et
# le forfait peut être injecté comme ligne de panier par PizzaPartyForfaitService.

pizza_party_new_name = "Pizza party privée – Nombre de personnes"
pizza_party_old_name = "Boule de pâte à pizza pour Pizza Party privée"

pizza_party_product =
  Product.find_by(name: pizza_party_new_name) ||
  Product.find_by(name: pizza_party_old_name) ||
  Product.new(name: pizza_party_new_name)

pizza_party_product.update!(
  name: pizza_party_new_name,
  description: "Une boule de pâte à pizza par personne pour ta Pizza party privée.",
  category: :dough_balls,
  position: 2,
  active: true,
  channel: "store",
  pizza_party_role: :party
)

ProductVariant.find_or_create_by!(product: pizza_party_product, name: "une boule") do |v|
  v.price_cents = 500
  v.active = true
  v.channel = "store"
end

forfait_product =
  Product.find_by(pizza_party_role: :forfait) ||
  Product.find_by(name: "Forfait Pizza party privée") ||
  Product.new(name: "Forfait Pizza party privée")

forfait_product.update!(
  name: "Forfait Pizza party privée",
  description: "Forfait Pizza party privée (matériel, four à bois). Ajouté automatiquement à ta commande.",
  category: :dough_balls,
  position: 3,
  active: true,
  channel: "admin",
  pizza_party_role: :forfait
)

ProductVariant.find_or_create_by!(product: forfait_product, name: "forfait") do |v|
  v.price_cents = 4000
  v.active = true
  v.channel = "store"
end

# --- Pizza party publique (#pizza-parties) ----------------------------------
# Produit public (variantes adulte/enfant), réservable depuis /evenements, hors
# catalogue. Base 4 Sources par variante (3 € adulte, 2 € enfant) ; base
# boulangers = prix − base. Pas de forfait.
public_party_product =
  Product.find_by(pizza_party_role: :public_party) ||
  Product.find_by(name: "Pizza party publique") ||
  Product.new(name: "Pizza party publique")

public_party_product.update!(
  name: "Pizza party publique",
  description: "Rejoins-nous pour une Pizza party ouverte à tous : chacun garnit et enfourne son pâton.",
  category: :dough_balls,
  position: 4,
  active: true,
  channel: "store",
  pizza_party_role: :public_party
)

ProductVariant.find_or_create_by!(product: public_party_product, name: "adulte") do |v|
  v.price_cents = 1000
  v.party_four_sources_base_cents = 300
  v.active = true
  v.channel = "store"
end

ProductVariant.find_or_create_by!(product: public_party_product, name: "enfant") do |v|
  v.price_cents = 600
  v.party_four_sources_base_cents = 200
  v.active = true
  v.channel = "store"
end
# ---------------------------------------------------------------------------

puts "✅ Products and variants created"

# Create some sample bake days for testing
# Next Tuesdays and Fridays with appropriate cut-offs across the next four months
today = Date.current
end_date = today + 4.months

[ 2, 5 ].each do |weekday|
  date = today + ((weekday - today.wday) % 7).days

  while date <= end_date
    unless BakeDay.exists?(baked_on: date)
      cut_off_at = BakeDay.calculate_cut_off_for(date)

      BakeDay.create!(
        baked_on: date,
        cut_off_at: cut_off_at
      )
    end
    date += 1.week
  end
end

puts "✅ Sample bake days created"

# Create sample orders for the next Friday based on the spreadsheet data
next_friday = today + ((5 - today.wday) % 7).days
next_friday_bake_day = BakeDay.find_by!(baked_on: next_friday)

variant_lookup = ProductVariant.includes(:product).each_with_object({}) do |variant, memo|
  memo[[ variant.product.name, variant.name ]] = variant
end

sample_orders = [
  {
    first_name: "Stéphanie",
    last_name: "de Tiège",
    phone_e164: "+32470000001",
    items: [
      { product_name: "Pain d'épeautre", variant_name: "600 g", qty: 1 },
      { product_name: "Pain au froment", variant_name: "1 kg", qty: 3 }
    ]
  },
  {
    first_name: "Sébastien",
    last_name: "Frennet",
    phone_e164: "+32470000002",
    items: [
      { product_name: "Pain d'épeautre", variant_name: "600 g", qty: 1 },
      { product_name: "Pain au froment", variant_name: "600 g", qty: 1 },
      { product_name: "Pain aux noix", variant_name: "600 g", qty: 1 }
    ]
  },
  {
    first_name: "Gaëlle",
    last_name: "de Fays",
    phone_e164: "+32470000003",
    items: [
      { product_name: "Pain aux céréales anciennes", variant_name: "600 g", qty: 1 }
    ]
  },
  {
    first_name: "Bruno",
    last_name: "S.",
    phone_e164: "+32470000004",
    items: [
      { product_name: "Pain d'épeautre", variant_name: "600 g", qty: 1 }
    ]
  },
  {
    first_name: "Verger",
    last_name: "Molignée",
    phone_e164: "+32470000005",
    items: [
      { product_name: "Pain au froment", variant_name: "600 g", qty: 20 }
    ]
  },
  {
    first_name: "Claire",
    last_name: "Roelandt",
    phone_e164: "+32470000006",
    items: [
      { product_name: "Pain aux noix/figues", variant_name: "600 g", qty: 1 }
    ]
  },
  {
    first_name: "Au fil de l'O",
    last_name: nil,
    phone_e164: "+32470000007",
    items: [
      { product_name: "Pain aux noix", variant_name: "600 g", qty: 1 }
    ]
  },
  {
    first_name: "Semisto",
    last_name: nil,
    phone_e164: "+32470000008",
    items: [
      { product_name: "Pain d'épeautre", variant_name: "600 g", qty: 1 }
    ]
  },
  {
    first_name: "Pierre",
    last_name: "Daene",
    phone_e164: "+32470000009",
    items: [
      { product_name: "Pain aux noix", variant_name: "1 kg", qty: 1 }
    ]
  },
  {
    first_name: "Laurence & Lau",
    last_name: nil,
    phone_e164: "+32470000010",
    items: [
      { product_name: "Pain aux graines", variant_name: "1 kg", qty: 2 },
      { product_name: "Pain aux graines", variant_name: "600 g", qty: 1 },
      { product_name: "Pain aux noix/figues", variant_name: "600 g", qty: 1 }
    ]
  }
]

sample_orders.each do |order_data|
  customer = Customer.find_or_create_by!(phone_e164: order_data[:phone_e164]) do |c|
    c.first_name = order_data[:first_name]
    c.last_name = order_data[:last_name]
  end

  customer.update!(first_name: order_data[:first_name], last_name: order_data[:last_name])

  order = Order.find_or_initialize_by(customer: customer, bake_day: next_friday_bake_day)
  order.status = :paid

  order.order_items.destroy_all if order.persisted?

  total_cents = 0

  order_data[:items].each do |item|
    variant = variant_lookup[[ item[:product_name], item[:variant_name] ]]
    raise "Unknown product variant for #{item.inspect}" unless variant

    unit_price_cents = variant.price_cents
    total_cents += unit_price_cents * item[:qty]

    order.order_items.build(
      product_variant: variant,
      qty: item[:qty],
      unit_price_cents: unit_price_cents
    )
  end

  order.total_cents = total_cents
  order.save!
end

puts "✅ Sample orders created"

# Artisan-boulangers (Stéphanie, Romane, Thomas)
%w[Stéphanie Romane Thomas].each do |name|
  Artisan.find_or_create_by!(name: name) do |a|
    a.active = true
  end
end

puts "✅ Artisans created"
