# frozen_string_literal: true

require "rails_helper"

# Générateur des captures d'écran du centre d'aide des boulangers.
#
# Ce n'est pas un test de régression : c'est un *outil* piloté par
# `bin/rails aide:screenshots`. Il pilote le vrai admin (Selenium headless),
# sur un jeu de données de démo réaliste et anonymisé (Faker FR — aucun vrai
# client), et enregistre chaque page dans app/assets/images/aide/SLUG.png.
#
# Les slugs viennent du manifeste app/docs/aide/screenshots.yml, référencé par
# les chapitres markdown via `![légende](shot:SLUG)`. Régénérer après tout
# changement de l'admin garde la doc fidèle à ce que le boulanger voit.
#
# Lancé seulement à la demande (tag :aide_screenshots, exclu du run normal).
RSpec.describe "Aide — génération des captures", type: :system, aide_screenshots: true do
  ASSET_DIR = Rails.root.join("app/assets/images/aide")
  MANIFEST = Rails.root.join("app/docs/aide/screenshots.yml")
  ADMIN_PASSWORD = "demo-boulanger"

  # Données de démo réalistes & anonymisées (noms/tél. fictifs via Faker FR).
  # Renvoie les enregistrements résolvables par le manifeste (`record:`).
  def build_demo_data
    Faker::Config.locale = "fr"

    breads = [
      [ "Pain d'épeautre", [ [ "1 kg", 550 ], [ "600 g", 350 ] ] ],
      [ "Pain au froment", [ [ "1 kg", 450 ], [ "600 g", 300 ] ] ],
      [ "Pain aux céréales anciennes", [ [ "1 kg", 600 ], [ "600 g", 380 ] ] ],
      [ "Pain de seigle", [ [ "800 g", 480 ] ] ]
    ]
    products = breads.each_with_index.map do |(name, variants), i|
      product = create(:product, name: name, position: i + 1, category: :breads)
      variants.each do |(vname, cents)|
        create(:product_variant, product: product, name: vname, price_cents: cents)
      end
      product
    end

    upcoming = create(:bake_day, :tuesday, :can_order)
    create(:bake_day, :past)

    customers = Array.new(9) do
      customer = create(:customer,
        first_name: Faker::Name.first_name,
        last_name: Faker::Name.last_name)
      create(:wallet, customer: customer, balance_cents: [ 0, 1200, 2500, 5000, 8000 ].sample)
      customer
    end

    statuses = %i[paid paid paid ready ready picked_up pending]
    orders = customers.first(7).each_with_index.map do |customer, i|
      variant = products.sample.product_variants.sample
      order = create(:order, customer: customer, bake_day: upcoming, status: statuses[i])
      create(:order_item, order: order, product_variant: variant, qty: [ 1, 1, 2 ].sample,
                          unit_price_cents: variant.price_cents)
      order.update!(total_cents: order.order_items.sum { |it| it.qty * it.unit_price_cents })
      order
    end

    create(:party_event, :public_party, title: "Pizza Party publique de l'été", held_on: Date.current + 14)
    create(:party_event, :public_party, title: "Pizza Party de la rentrée", held_on: Date.current + 35)

    { order: orders.first, bake_day: upcoming, customer: customers.first, product: products.first }
  end

  def resolve_path(entry, records)
    return entry["path"] if entry["path"].present?

    record = records[entry["record"].to_sym]
    raise "Aucun enregistrement de démo pour record=#{entry['record']}" unless record

    case entry["record"]
    when "order"     then "/admin/orders/#{record.id}"
    when "bake_day"  then "/admin/bake_days/#{record.id}"
    when "customer"  then "/admin/customers/#{record.id}"
    when "product"   then "/admin/products/#{record.id}"
    else raise "record inconnu : #{entry['record']}"
    end
  end

  def sign_in_admin
    visit "/admin/login"
    fill_in "password", with: ADMIN_PASSWORD
    click_button "Se connecter"
    # Attendre la confirmation : on doit avoir quitté la page de login, sinon la
    # connexion a échoué (et toutes les captures suivantes seraient des pages de
    # login). On échoue bruyamment plutôt que de produire une doc trompeuse.
    Timeout.timeout(10) do
      sleep 0.1 while current_path.to_s.include?("/admin/login")
    end
  rescue Timeout::Error
    raise "Connexion admin échouée : toujours sur /admin/login après soumission."
  end

  def on_login_page?
    current_path.to_s.include?("/admin/login") || page.has_text?("Connexion admin", wait: 0)
  end

  def capture(path, slug, selector, needs_auth)
    ASSET_DIR.mkpath
    target = ASSET_DIR.join("#{slug}.png")

    visit path
    # Garde-fou : si une page authentifiée rebondit vers le login (session
    # perdue), on se reconnecte une fois et on revient.
    if needs_auth && on_login_page?
      sign_in_admin
      visit path
    end
    raise "Capture #{slug} : page de login inattendue sur #{path}" if needs_auth && on_login_page?
    # Attendre le rendu, puis agrandir la fenêtre à la hauteur du contenu pour
    # une capture pleine page (bornée à 4000 px).
    sleep 0.3
    content_height = page.evaluate_script("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)").to_i
    height = (content_height + 40).clamp(800, 4000)
    page.driver.browser.manage.window.resize_to(1280, height)

    png =
      if selector.present? && page.has_css?(selector, wait: 2)
        page.find(selector, match: :first).native.screenshot_as(:png)
      else
        page.driver.browser.screenshot_as(:png)
      end
    File.binwrite(target, png)
    target
  end

  it "génère toutes les captures du manifeste" do
    original_pw = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = ADMIN_PASSWORD

    entries = YAML.safe_load_file(MANIFEST)
    records = build_demo_data
    page.driver.browser.manage.window.resize_to(1280, 900)

    signed_in = false
    generated = []

    entries.each do |entry|
      slug = entry["slug"]
      needs_auth = entry.fetch("auth", true)
      if needs_auth && !signed_in
        sign_in_admin
        signed_in = true
      end

      path = resolve_path(entry, records)
      file = capture(path, slug, entry["selector"], needs_auth)
      generated << file
      expect(File.size(file)).to be > 1000, "capture vide pour #{slug} (#{path})"
    end

    puts "\n[aide:screenshots] #{generated.size} captures générées dans #{ASSET_DIR}"
    generated.each { |f| puts "  ✓ #{f.basename}" }
  ensure
    ENV["ADMIN_PASSWORD"] = original_pw
  end
end
