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
dough_balls = [
  {
    name: "Boule de pâte à pizza à emporter",
    description: "Boule de pâte à pizza à emporter",
    position: 1,
    variants: [
      { name: "une boule", price_cents: 200 }
    ]
  },
  {
    name: "Boule de pâte à pizza pour Pizza Party privée",
    description: "Boule de pâte à pizza pour Pizza Party privée",
    position: 2,
    variants: [
      { name: "une boule", price_cents: 500 }
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

puts "✅ Products and variants created"

# Create some sample bake days for testing
# Next Tuesdays and Fridays with appropriate cut-offs across the next four months
today = Date.current
end_date = today + 4.months

[2, 5].each do |weekday|
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
  memo[[variant.product.name, variant.name]] = variant
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
    variant = variant_lookup[[item[:product_name], item[:variant_name]]]
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
