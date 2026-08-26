class BackfillPizzaPartyRolesAndPublicParty < ActiveRecord::Migration[8.0]
  # Corrige en prod les rôles pizza party jamais positionnés (les seeds n'avaient
  # pas été rejoués depuis l'ajout de `pizza_party_role`) et crée la party
  # publique. IDEMPOTENT, et SANS aucune donnée de test (contrairement à
  # `db:seed`, qui injecterait de fausses fournées/commandes).
  #
  # Effets attendus :
  #   - la party privée redevient reconnue (retirée du catalogue, réservable sur
  #     /evenements, forfait 40 € de nouveau auto-synchronisé) ;
  #   - la party publique (variantes adulte/enfant + bases 4 Sources) devient
  #     disponible.
  def up
    backfill_private_party
    backfill_forfait
    backfill_public_party
  end

  def down
    # Données métier : non réversible automatiquement.
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def backfill_private_party
    product =
      Product.find_by(pizza_party_role: :party) ||
      Product.find_by(name: "Pizza party privée – Nombre de personnes") ||
      Product.find_by(name: "Boule de pâte à pizza pour Pizza Party privée")

    unless product
      say "Produit party privée introuvable — rôle non positionné (à vérifier manuellement)."
      return
    end

    product.update!(name: "Pizza party privée – Nombre de personnes", pizza_party_role: :party)
    ensure_variant(product, "une boule", price_cents: 500)
    say "Party privée : rôle :party positionné (##{product.id})."
  end

  def backfill_forfait
    product =
      Product.find_by(pizza_party_role: :forfait) ||
      Product.find_by(name: "Forfait Pizza party privée") ||
      Product.new(name: "Forfait Pizza party privée")

    product.assign_attributes(
      name: "Forfait Pizza party privée",
      description: "Forfait Pizza party privée (matériel, four à bois). Ajouté automatiquement à ta commande.",
      category: :dough_balls,
      active: true,
      channel: "admin",
      pizza_party_role: :forfait
    )
    product.position ||= 3
    product.save!
    # La variante forfait reste en `channel: "store"` pour survivre au filtre
    # panier (comme le seed) : c'est elle que PizzaPartyForfaitService injecte.
    ensure_variant(product, "forfait", price_cents: 4000)
    say "Forfait Pizza party : présent, rôle :forfait (##{product.id})."
  end

  def backfill_public_party
    product =
      Product.find_by(pizza_party_role: :public_party) ||
      Product.find_by(name: "Pizza party publique") ||
      Product.new(name: "Pizza party publique")

    product.assign_attributes(
      name: "Pizza party publique",
      description: "Rejoins-nous pour une Pizza party ouverte à tous : chacun garnit et enfourne son pâton.",
      category: :dough_balls,
      active: true,
      channel: "store",
      pizza_party_role: :public_party
    )
    product.position ||= 4
    product.save!

    ensure_variant(product, "adulte", price_cents: 1000, party_four_sources_base_cents: 300)
    ensure_variant(product, "enfant", price_cents: 600, party_four_sources_base_cents: 200)
    say "Party publique : produit + variantes adulte/enfant (##{product.id})."
  end

  # Crée la variante si absente ; ne réécrit jamais un prix/une base déjà saisis.
  def ensure_variant(product, name, price_cents:, party_four_sources_base_cents: nil)
    variant = product.product_variants.find_or_initialize_by(name: name)
    variant.price_cents ||= price_cents
    variant.party_four_sources_base_cents ||= party_four_sources_base_cents if party_four_sources_base_cents
    variant.active = true if variant.active.nil?
    variant.channel ||= "store"
    variant.save!
  end
end
