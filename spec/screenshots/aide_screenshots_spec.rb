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
# Les captures servent aussi de preuve visuelle aux refontes de l'admin : le
# jeu de démo est donc DÉTERMINISTE (graine fixe). Sans elle, chaque exécution
# réécrivait les PNG avec de nouveaux noms et montants, et le diff d'une PR de
# restyle devenait illisible. Restent variables — de quelques pixels — les
# dates (calendrier réel) et les libellés relatifs au temps (compte à rebours
# de clôture, « il y a … ») : deux exécutions le même jour laissent la grande
# majorité des PNG identiques à l'octet près.
#
# Lancé seulement à la demande (tag :aide_screenshots, exclu du run normal).
RSpec.describe "Aide — génération des captures", type: :system, aide_screenshots: true do
  ASSET_DIR = Rails.root.join("app/assets/images/aide")
  MANIFEST = Rails.root.join("app/docs/aide/screenshots.yml")
  ADMIN_PASSWORD = "demo-boulanger"
  DEMO_SEED = 20_260_820
  # Fenêtre de référence : largeur des captures, et hauteur minimale à laquelle
  # on revient avant de mesurer chaque page.
  BASE_VIEWPORT = [ 1280, 900 ].freeze
  # Plafond d'une capture pleine page : au-delà, Chrome assemble plusieurs
  # tuiles et répète les éléments fixes.
  MAX_CAPTURE_HEIGHT = 4000

  # Fiche par défaut d'un `record:` cité sans `path:` dans le manifeste.
  # Un enregistrement sans page de fiche (un groupe, un lieu de retrait) doit
  # être accompagné d'un `path:` explicite.
  RECORD_SHOW_PATHS = {
    "order" => "/admin/orders/:id",
    "bake_day" => "/admin/bake_days/:id",
    "customer" => "/admin/customers/:id",
    "product" => "/admin/products/:id",
    "flour" => "/admin/parametres/farines/:id/edit"
  }.freeze

  # Marqueurs des pages d'erreur Rails : une capture qui en contient un n'est
  # pas une preuve visuelle, c'est une panne. On échoue plutôt que de publier.
  ERROR_MARKERS = [
    "Action Controller: Exception caught",
    "We're sorry, but something went wrong"
  ].freeze

  # Données de démo réalistes & anonymisées (noms/tél. fictifs via Faker FR).
  # Renvoie les enregistrements résolvables par le manifeste (`record:`).
  def build_demo_data
    Faker::Config.locale = "fr"
    Faker::Config.random = Random.new(DEMO_SEED)
    rng = Random.new(DEMO_SEED)

    flours = build_flours
    mold_types = build_mold_types
    build_ingredients
    build_sales_locations
    build_revenue_parameters

    products = build_catalog(flours, mold_types)
    pickup_locations = build_pickup_locations
    bake_days = build_bake_days(pickup_locations)
    build_artisans(bake_days)
    groups = build_groups
    customers = build_customers(groups, rng)
    orders = build_orders(products, bake_days, customers, pickup_locations, rng)
    build_pro_billing(products, bake_days)
    build_parties

    {
      order: orders.first,
      bake_day: bake_days[:upcoming],
      customer: customers.first,
      product: products.first,
      # Farine de démo (#211) : le chapitre « quantités et recettes » montre le
      # formulaire de ratios de panification.
      flour: flours[:froment],
      group: groups.first,
      pickup_location: pickup_locations.first
    }
  end

  def build_flours
    {
      froment: create(:flour, name: "Froment T80", position: 1),
      epeautre: create(:flour, name: "Épeautre T110", position: 2),
      seigle: create(:flour, :seigle, name: "Seigle T130", position: 3)
    }
  end

  def build_mold_types
    {
      grand: MoldType.create!(name: "Moule 1 kg", limit: 40, position: 1),
      petit: MoldType.create!(name: "Moule 600 g", limit: 60, position: 2)
    }
  end

  def build_ingredients
    [
      [ "Graines de tournesol", :weight, 1 ],
      [ "Graines de courge", :weight, 2 ],
      [ "Noix", :weight, 3 ]
    ].map { |(name, unit, position)| Ingredient.create!(name: name, unit_type: unit, position: position) }
  end

  def build_sales_locations
    [
      create(:sales_location, name: "Marché de Yvoir", position: 1),
      create(:sales_location, name: "Marché de Dinant", position: 2)
    ]
  end

  # Paramètres de revenus : sans eux les pages « revenus boulangers » et le
  # reporting associé n'affichent que des tirets.
  def build_revenue_parameters
    create(:revenue_parameter, :transport)
    create(:revenue_parameter, :four_sources_rate)
    partnership = create(:revenue_partnership, name: "Duo du mardi")
    create(:revenue_partnership_membership, revenue_partnership: partnership, artisan: create(:artisan, name: "Camille"))
  end

  # Catalogue : chaque pain porte sa farine (100 %, la somme doit valoir 100)
  # et ses formats, avec la quantité de farine et le moule qui alimentent le
  # calcul des capacités (pétrin, four, moules).
  def build_catalog(flours, mold_types)
    breads = [
      [ "Pain d'épeautre", :epeautre, [ [ "1 kg", 550, 700, :grand ], [ "600 g", 350, 420, :petit ] ] ],
      [ "Pain au froment", :froment, [ [ "1 kg", 450, 700, :grand ], [ "600 g", 300, 420, :petit ] ] ],
      [ "Pain aux céréales anciennes", :froment, [ [ "1 kg", 600, 700, :grand ], [ "600 g", 380, 420, :petit ] ] ],
      [ "Pain de seigle", :seigle, [ [ "800 g", 480, 560, :grand ] ] ]
    ]

    breads.each_with_index.map do |(name, flour_key, variants), i|
      product = create(:product, name: name, position: i + 1, category: :breads)
      product.product_flours.create!(flour: flours.fetch(flour_key), percentage: 100)
      variants.each do |(vname, cents, flour_quantity, mold_key)|
        create(:product_variant, product: product, name: vname, price_cents: cents,
                                 flour_quantity: flour_quantity, mold_type: mold_types.fetch(mold_key))
      end
      product
    end
  end

  # Le lieu par défaut d'abord : la fabrique de fournée s'appuie dessus.
  def build_pickup_locations
    default = PickupLocation.default_location || create(:pickup_location, :default)
    [
      default,
      create(:pickup_location, name: "Marché de Yvoir", description: "Le vendredi matin, place communale.", position: 1),
      create(:pickup_location, name: "Épicerie Le Panier", description: "Retrait aux heures d'ouverture du magasin.", position: 2)
    ]
  end

  def build_bake_days(pickup_locations)
    upcoming = create(:bake_day, :tuesday, :can_order)
    upcoming.update!(pickup_location_ids: pickup_locations.map(&:id))
    { upcoming: upcoming, past: create(:bake_day, :past) }
  end

  def build_artisans(bake_days)
    artisans = [ create(:artisan, name: "Louise"), create(:artisan, name: "Mathieu") ]
    artisans.each do |artisan|
      create(:artisan_revenue_share, artisan: artisan, percent: 50)
      bake_days.each_value { |bake_day| create(:bake_day_artisan, bake_day: bake_day, artisan: artisan) }
    end
    artisans
  end

  def build_groups
    [
      create(:group, name: "Coopérative du village", discount_percent: 10),
      create(:group, name: "Voisins de Bauche", discount_percent: 5),
      create(:group, name: "Bénévoles", discount_percent: 0)
    ]
  end

  def build_customers(groups, rng)
    Array.new(9) do |i|
      customer = create(:customer,
        first_name: Faker::Name.first_name,
        last_name: Faker::Name.last_name)
      create(:wallet, customer: customer, balance_cents: [ 0, 1200, 2500, 5000, 8000 ].sample(random: rng))
      create(:customer_group, customer: customer, group: groups[i % groups.size]) if i < 4
      customer
    end
  end

  def build_orders(products, bake_days, customers, pickup_locations, rng)
    statuses = %i[paid paid paid ready ready picked_up pending]

    customers.first(7).each_with_index.map do |customer, i|
      variant = products.sample(random: rng).product_variants.sample(random: rng)
      order = create(:order, customer: customer, bake_day: bake_days[:upcoming], status: statuses[i],
                             pickup_location: pickup_locations[i % pickup_locations.size])
      create(:order_item, order: order, product_variant: variant, qty: [ 1, 1, 2 ].sample(random: rng),
                          unit_price_cents: variant.price_cents)
      order.update!(total_cents: order.order_items.sum { |it| it.qty * it.unit_price_cents })
      order
    end
  end

  # Client professionnel facturé au mois : sans lui, /admin/billing est vide.
  # Une commande sur chaque fournée pour que le mois en cours en contienne au
  # moins une, quel que soit le jour où les captures sont régénérées.
  def build_pro_billing(products, bake_days)
    pro = create(:customer, first_name: "Épicerie", last_name: "du Val", billable: true)
    create(:wallet, customer: pro, balance_cents: 0)

    [ [ bake_days[:past], :picked_up ], [ bake_days[:upcoming], :unpaid ] ].each do |(bake_day, status)|
      order = create(:order, customer: pro, bake_day: bake_day, status: status)
      products.first(3).each do |product|
        variant = product.product_variants.first
        create(:order_item, order: order, product_variant: variant, qty: 4, unit_price_cents: variant.price_cents)
      end
      order.update!(total_cents: order.order_items.sum { |it| it.qty * it.unit_price_cents })
    end

    pro
  end

  def build_parties
    create(:party_event, :public_party, title: "Pizza Party publique de l'été", held_on: Date.current + 14)
    create(:party_event, :public_party, title: "Pizza Party de la rentrée", held_on: Date.current + 35)
    create(:party_slot_block, blocked_on: Date.current + 21, slot: :soir)
  end

  def resolve_path(entry, records)
    record_key = entry["record"]
    return entry["path"] if record_key.blank?

    template = entry["path"].presence || RECORD_SHOW_PATHS[record_key]
    raise "record=#{record_key} n'a pas de fiche par défaut : ajoute un `path:` au manifeste" if template.nil?

    record = records[record_key.to_sym]
    raise "Aucun enregistrement de démo pour record=#{record_key}" unless record

    path = template.sub(":id", record.id.to_s)

    # `:variant_id` (#211) : la fiche d'une variante demande DEUX ids. On prend
    # la première variante du produit résolu — le jeu de démo est déterministe,
    # donc la capture l'est aussi.
    if path.include?(":variant_id")
      variant = record.respond_to?(:product_variants) ? record.product_variants.order(:id).first : nil
      raise "record=#{record_key} n'a pas de variante pour :variant_id" if variant.nil?

      path = path.sub(":variant_id", variant.id.to_s)
    end

    path
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

  def error_page?
    ERROR_MARKERS.any? { |marker| page.has_text?(marker, wait: 0) }
  end

  def resize_window(width, height)
    page.driver.browser.manage.window.resize_to(width, height)
  end

  # Étire la fenêtre à la hauteur du contenu (bornée) pour une capture pleine
  # page. `resize_to` dimensionne la FENÊTRE, barre d'outils comprise : on
  # ajoute l'écart avec la hauteur utile, sinon le bas de la page est rogné.
  def fit_window_to_content
    content_height = page.evaluate_script("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)").to_i
    chrome_height = BASE_VIEWPORT.last - page.evaluate_script("window.innerHeight").to_i
    viewport_height = (content_height + 40).clamp(BASE_VIEWPORT.last, MAX_CAPTURE_HEIGHT)
    resize_window(BASE_VIEWPORT.first, viewport_height + chrome_height)
  end

  def capture(path, slug, selector, needs_auth)
    ASSET_DIR.mkpath
    target = ASSET_DIR.join("#{slug}.png")

    # Repartir de la fenêtre de référence : le layout admin est en
    # `min-h-screen`, donc une page courte mesurée dans la fenêtre étirée de la
    # capture précédente hérite de sa hauteur — PNG à moitié vide, et barre
    # latérale répétée par l'assemblage de Chrome.
    resize_window(*BASE_VIEWPORT)
    visit path
    # Garde-fou : si une page authentifiée rebondit vers le login (session
    # perdue), on se reconnecte une fois et on revient.
    if needs_auth && on_login_page?
      sign_in_admin
      visit path
    end
    raise "Capture #{slug} : page de login inattendue sur #{path}" if needs_auth && on_login_page?
    raise "Capture #{slug} : page d'erreur sur #{path}" if error_page?
    # Attendre le rendu, puis agrandir la fenêtre à la hauteur du contenu.
    sleep 0.3
    fit_window_to_content

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
    original_random = Faker::Config.random
    ENV["ADMIN_PASSWORD"] = ADMIN_PASSWORD

    entries = YAML.safe_load_file(MANIFEST)
    records = build_demo_data
    resize_window(*BASE_VIEWPORT)

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
    Faker::Config.random = original_random
  end
end
