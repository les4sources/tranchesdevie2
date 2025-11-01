# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Products and variants according to PRD

# Category: Breads
breads = [
  {
    name: "Spelt bread",
    description: "Pain d'épeautre",
    position: 1,
    variants: [
      { name: "1 kg", price_cents: 550 },
      { name: "600 g", price_cents: 350 }
    ]
  },
  {
    name: "Wheat bread",
    description: "Pain de blé",
    position: 2,
    variants: [
      { name: "1 kg", price_cents: 450 },
      { name: "600 g", price_cents: 300 }
    ]
  },
  {
    name: "Ancient grains bread",
    description: "Pain aux céréales anciennes",
    position: 3,
    variants: [
      { name: "600 g", price_cents: 550 }
    ]
  },
  {
    name: "Walnut bread",
    description: "Pain aux noix",
    position: 4,
    variants: [
      { name: "1 kg", price_cents: 550 },
      { name: "600 g", price_cents: 400 }
    ]
  },
  {
    name: "Seeded bread",
    description: "Pain aux graines",
    position: 5,
    variants: [
      { name: "1 kg", price_cents: 550 },
      { name: "600 g", price_cents: 400 }
    ]
  },
  {
    name: "Walnut/fig bread",
    description: "Pain noix/figues",
    position: 6,
    variants: [
      { name: "600 g", price_cents: 400 }
    ]
  },
  {
    name: "Choco/sugar bread",
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
    name: "Take‑away pizza dough ball",
    description: "Boule de pâte à pizza à emporter",
    position: 1,
    variants: [
      { name: "Unité", price_cents: 200 }
    ]
  },
  {
    name: "Private Pizza Party dough ball",
    description: "Boule de pâte à pizza pour fête privée",
    position: 2,
    variants: [
      { name: "Unité", price_cents: 500 }
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
# Next Tuesday and Friday with appropriate cut-offs
today = Date.current
next_tuesday = today + ((2 - today.wday) % 7).days
next_friday = today + ((5 - today.wday) % 7).days

[next_tuesday, next_friday].each do |date|
  next if BakeDay.exists?(baked_on: date)

  cut_off_at = BakeDay.calculate_cut_off_for(date)
  
  BakeDay.create!(
    baked_on: date,
    cut_off_at: cut_off_at
  )
end

puts "✅ Sample bake days created"
