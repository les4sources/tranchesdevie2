# frozen_string_literal: true

# Seeds pour la génération de captures d'écran de la documentation
# boulanger (docs/admin). Idempotent : appelable plusieurs fois sans doublon.
#
# Ne PAS exécuter sur une base de production ou de dev locale. Le point
# d'entrée officiel est `rake docs:seed_demo`, qui force RAILS_ENV=test.
#
# Politique de noms : tout ce qui apparaît à l'écran est **stable et
# reconnaissable** (Marie Dubois, Farine T65, Miche…) pour que les captures
# aient un rendu didactique et ne changent pas d'une exécution à l'autre.

require "faker" if defined?(Rails) && Rails.env.test?

module DemoSeeds
  ADMIN_PASSWORD = ENV["ADMIN_PASSWORD"].presence || "demo"

  # Base de temps : le lundi qui précède la prochaine cuisson du mardi.
  # On garde les cuissons dans le futur pour que `cut_off_passed?` reste
  # false — sinon le bouton « Rembourser » et d'autres actions disparaissent
  # des captures.
  def self.reference_monday
    Date.current.next_occurring(:monday)
  end

  def self.seed!
    ActiveRecord::Base.transaction do
      seed_production_setting
      flours = seed_flours
      mold_types = seed_mold_types
      seed_ingredients
      artisans = seed_artisans
      groups = seed_groups
      products = seed_products(flours, mold_types)
      customers = seed_customers(groups)
      bake_days = seed_bake_days(artisans)
      seed_orders(customers, bake_days, products)
    end
  end

  def self.seed_production_setting
    setting = ProductionSetting.instance
    setting.update!(
      oven_capacity_grams: 110_000,
      market_day_oven_capacity_grams: 165_000
    )
    setting
  end

  def self.seed_flours
    [
      { name: "Farine T65 bio", kneader_limit_grams: 30_000 },
      { name: "Farine T80 bio", kneader_limit_grams: 25_000 },
      { name: "Farine de seigle bio", kneader_limit_grams: 15_000 },
      { name: "Farine d'épeautre bio", kneader_limit_grams: 20_000 }
    ].map do |attrs|
      Flour.find_or_create_by!(name: attrs[:name]) do |f|
        f.kneader_limit_grams = attrs[:kneader_limit_grams]
      end
    end
  end

  def self.seed_mold_types
    [
      { name: "Moule à miche 500g", limit: 40 },
      { name: "Moule à miche 1kg", limit: 25 },
      { name: "Moule à baguette", limit: 60 },
      { name: "Moule à brioche", limit: 20 }
    ].map do |attrs|
      MoldType.find_or_create_by!(name: attrs[:name]) do |m|
        m.limit = attrs[:limit]
      end
    end
  end

  def self.seed_ingredients
    [
      { name: "Sel de Guérande", unit: "weight" },
      { name: "Levain", unit: "weight" },
      { name: "Graines de tournesol", unit: "weight" },
      { name: "Noix", unit: "weight" }
    ].each do |attrs|
      next unless defined?(Ingredient)
      Ingredient.find_or_create_by!(name: attrs[:name])
    end
  end

  def self.seed_artisans
    [
      { name: "Marc Dupont" },
      { name: "Lucie Meyer" }
    ].map do |attrs|
      Artisan.find_or_create_by!(name: attrs[:name]) do |a|
        a.active = true
      end
    end
  end

  def self.seed_groups
    [
      { name: "Grand public", discount_percent: 0 },
      { name: "Écoles & associations", discount_percent: 10 },
      { name: "Revendeurs", discount_percent: 20 }
    ].map do |attrs|
      Group.find_or_create_by!(name: attrs[:name]) do |g|
        g.discount_percent = attrs[:discount_percent]
      end
    end
  end

  def self.seed_products(flours, mold_types)
    t65 = flours.find { |f| f.name.include?("T65") }
    t80 = flours.find { |f| f.name.include?("T80") }
    seigle = flours.find { |f| f.name.include?("seigle") }
    miche_500 = mold_types.find { |m| m.name.include?("500g") }
    miche_1kg = mold_types.find { |m| m.name.include?("1kg") }

    products = []

    products << upsert_product(
      name: "Miche de campagne",
      short_name: "Miche",
      category: :breads,
      position: 1,
      variants: [
        { name: "500 g", price_cents: 550, flour_quantity: 400, mold_type: miche_500 },
        { name: "1 kg", price_cents: 950, flour_quantity: 800, mold_type: miche_1kg }
      ],
      flour_composition: { t65 => 80, seigle => 20 }
    )

    products << upsert_product(
      name: "Pain intégral",
      short_name: "Intégral",
      category: :breads,
      position: 2,
      variants: [
        { name: "500 g", price_cents: 600, flour_quantity: 400, mold_type: miche_500 },
        { name: "1 kg", price_cents: 1050, flour_quantity: 800, mold_type: miche_1kg }
      ],
      flour_composition: { t80 => 100 }
    )

    products << upsert_product(
      name: "Pain aux graines",
      short_name: "Graines",
      category: :breads,
      position: 3,
      variants: [
        { name: "500 g", price_cents: 650, flour_quantity: 400, mold_type: miche_500 }
      ],
      flour_composition: { t65 => 60, t80 => 40 }
    )

    products
  end

  def self.upsert_product(name:, short_name:, category:, position:, variants:, flour_composition:)
    product = Product.find_or_initialize_by(name: name)
    product.assign_attributes(
      short_name: product.respond_to?(:short_name) ? short_name : nil,
      category: category,
      position: position,
      active: true,
      channel: "store",
      internal_category: :boulangerie
    ).compact
    product.save!(validate: false)

    variants.each_with_index do |v, idx|
      variant = product.product_variants.find_or_initialize_by(name: v[:name])
      variant.assign_attributes(
        price_cents: v[:price_cents],
        flour_quantity: v[:flour_quantity],
        active: true,
        position: idx + 1
      )
      variant.mold_type = v[:mold_type] if variant.respond_to?(:mold_type=)
      variant.save!(validate: false)
    end

    flour_composition.each do |flour, percentage|
      next unless defined?(ProductFlour)
      pf = ProductFlour.find_or_initialize_by(product: product, flour: flour)
      pf.percentage = percentage
      pf.save!(validate: false)
    end

    product
  end

  def self.seed_customers(groups)
    grand_public = groups.find { |g| g.discount_percent.zero? }
    ecoles = groups.find { |g| g.discount_percent == 10 }

    demos = [
      { first_name: "Marie",   last_name: "Dubois",  phone: "+32478111001", email: "marie.dubois@example.be",   group: grand_public },
      { first_name: "Pierre",  last_name: "Martin",  phone: "+32478111002", email: "pierre.martin@example.be",  group: grand_public },
      { first_name: "Sophie",  last_name: "Laurent", phone: "+32478111003", email: "sophie.laurent@example.be", group: grand_public },
      { first_name: "Julien",  last_name: "Petit",   phone: "+32478111004", email: "julien.petit@example.be",   group: ecoles },
      { first_name: "Camille", last_name: "Renard",  phone: "+32478111005", email: nil,                          group: grand_public }
    ]

    demos.map do |attrs|
      customer = Customer.find_or_initialize_by(phone_e164: attrs[:phone])
      customer.assign_attributes(
        first_name: attrs[:first_name],
        last_name: attrs[:last_name],
        email: attrs[:email],
        sms_opt_out: false
      )
      customer.groups = [ attrs[:group] ].compact if customer.respond_to?(:groups=)
      customer.save!(validate: false)
      customer
    end
  end

  def self.seed_bake_days(artisans)
    monday = reference_monday
    tuesday = monday + 1.day
    friday = monday + 4.days

    bake_days = [ tuesday, friday ].map do |date|
      cut_off = BakeDay.calculate_cut_off_for(date) || (date - 1.day).beginning_of_day + 18.hours
      day = BakeDay.find_or_initialize_by(baked_on: date)
      day.cut_off_at = cut_off
      day.market_day = (date == friday)
      day.internal_note = "Journée test — préparer les commandes de #{date.strftime('%A %d/%m')}"
      day.save!(validate: false)
      day.baking_artisan_ids = artisans.map(&:id) if day.respond_to?(:baking_artisan_ids=)
      day.save!(validate: false)
      day
    end

    bake_days
  end

  def self.seed_orders(customers, bake_days, products)
    return if bake_days.empty?

    scenarios = [
      { customer: 0, bake_day: 0, status: :paid,      items: [ [ 0, 0, 2 ], [ 1, 0, 1 ] ] },
      { customer: 1, bake_day: 0, status: :paid,      items: [ [ 0, 1, 1 ] ] },
      { customer: 2, bake_day: 0, status: :ready,     items: [ [ 2, 0, 3 ] ] },
      { customer: 3, bake_day: 1, status: :paid,      items: [ [ 0, 0, 5 ], [ 1, 1, 2 ] ] },
      { customer: 4, bake_day: 1, status: :unpaid,    items: [ [ 2, 0, 1 ] ] }
    ]

    scenarios.each_with_index do |sc, idx|
      customer = customers[sc[:customer]]
      bake_day = bake_days[sc[:bake_day]]
      next unless customer && bake_day

      order_number = "TV-#{bake_day.baked_on.strftime('%Y%m%d')}-#{(idx + 1).to_s.rjust(4, '0')}"
      order = Order.find_or_initialize_by(order_number: order_number)
      order.assign_attributes(
        customer: customer,
        bake_day: bake_day,
        status: sc[:status],
        source: :checkout,
        requires_invoice: false
      )
      order.save!(validate: false)

      order.order_items.destroy_all
      total_cents = 0
      sc[:items].each do |(product_idx, variant_idx, qty)|
        product = products[product_idx]
        variant = product&.product_variants&.[](variant_idx)
        next unless variant
        item = order.order_items.build(
          product_variant: variant,
          qty: qty,
          unit_price_cents: variant.price_cents
        )
        item.save!(validate: false)
        total_cents += qty * variant.price_cents
      end
      order.update_columns(total_cents: total_cents) if total_cents.positive?
    end
  end
end

DemoSeeds.seed! if $PROGRAM_NAME == __FILE__ || defined?(Rake)
