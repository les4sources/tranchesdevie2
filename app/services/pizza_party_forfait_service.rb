# Synchronise la ligne « forfait Pizza party » (#68) dans un panier session.
#
# Le panier est un array de hashes à clés string :
#   { "product_variant_id" => id.to_s, "qty" => n, "name" => ..., "price_cents" => ... }
#
# Règle métier :
#   - si le panier (hors forfait) contient AU MOINS une ligne dont la variante
#     appartient à un produit `pizza_party_role: :party`, alors le panier doit
#     contenir EXACTEMENT UNE ligne forfait (qty 1, prix 4000) ;
#   - sinon, toute ligne forfait est retirée.
#
# Le forfait est ainsi une simple ligne de panier auto-synchronisée : tout le
# downstream (totaux, PaymentIntent, OrderCreationService, webhook, page succès)
# s'appuie sur le panier sans cas particulier. Le forfait est donc compté une
# seule fois par commande quel que soit le nombre de boules.
#
# La méthode est idempotente : `sync(sync(cart)) == sync(cart)`. Elle ne mute
# pas le panier reçu (renvoie un nouvel array) et ne crashe pas si le produit
# forfait est absent de la base (cas d'une base sans seeds) : dans ce cas, elle
# se contente de retirer toute ligne forfait résiduelle.
class PizzaPartyForfaitService
  FORFAIT_PRICE_CENTS = 4000
  FORFAIT_QTY = 1

  def self.sync(cart)
    new(cart).sync
  end

  def initialize(cart)
    @cart = Array(cart)
  end

  def sync
    forfait_variant = self.class.forfait_variant
    forfait_variant_id = forfait_variant&.id&.to_s

    # Panier débarrassé de toute ligne forfait existante (on la reconstruit).
    base_cart =
      if forfait_variant_id
        @cart.reject { |item| item["product_variant_id"].to_s == forfait_variant_id }
      else
        # Pas de produit forfait en base : on retire au moins toute ligne dont la
        # variante pointe vers un produit forfait (défensif), sinon on garde tout.
        reject_forfait_lines(@cart)
      end

    return base_cart unless forfait_variant
    return base_cart unless party_present?(base_cart)

    base_cart + [ forfait_line(forfait_variant) ]
  end

  # Le panier contient-il une Pizza party privée ? (Un tel panier se date par un
  # PartyEvent, pas par une fournée — cf. PartyReservationService.)
  def self.party_cart?(cart)
    new(cart).send(:party_present?, Array(cart))
  end

  # Le panier contient-il des articles ordinaires (ni party privée, ni forfait) ?
  # Sert au refus des paniers mixtes pain + party : une commande party n'a pas de
  # fournée, du pain dedans n'apparaîtrait sur aucune feuille de production.
  def self.regular_items?(cart)
    variant_ids = Array(cart).map { |item| item["product_variant_id"].to_s }.reject(&:blank?).uniq
    return false if variant_ids.empty?

    ProductVariant
      .joins(:product)
      .where(id: variant_ids)
      .where.not(products: { pizza_party_role: [
        Product.pizza_party_roles[:party], Product.pizza_party_roles[:forfait]
      ] })
      .exists?
  end

  # Variante « store » du produit forfait, ou nil si absent (base sans seeds).
  def self.forfait_variant
    product = Product.pizza_party_forfait.first
    return nil unless product

    product.product_variants.find_by(channel: "store") ||
      product.product_variants.first
  end

  private

  # Le panier contient-il au moins une variante d'un produit « party » ?
  def party_present?(cart)
    variant_ids = cart.map { |item| item["product_variant_id"].to_s }.reject(&:blank?).uniq
    return false if variant_ids.empty?

    ProductVariant
      .joins(:product)
      .where(id: variant_ids, products: { pizza_party_role: Product.pizza_party_roles[:party] })
      .exists?
  end

  def reject_forfait_lines(cart)
    forfait_variant_ids =
      ProductVariant
        .joins(:product)
        .where(products: { pizza_party_role: Product.pizza_party_roles[:forfait] })
        .pluck(:id)
        .map(&:to_s)

    return cart if forfait_variant_ids.empty?

    cart.reject { |item| forfait_variant_ids.include?(item["product_variant_id"].to_s) }
  end

  def forfait_line(variant)
    {
      "product_variant_id" => variant.id.to_s,
      "qty" => FORFAIT_QTY,
      "name" => variant.name,
      "price_cents" => FORFAIT_PRICE_CENTS
    }
  end
end
