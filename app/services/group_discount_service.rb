# Calcule la remise applicable à un client, ligne par ligne.
#
# Règles (cf. #87) :
# - Pour une ligne, la remise retenue est la MEILLEURE parmi tous les groupes du
#   client. Pour chaque groupe, la règle la plus spécifique gagne (remise ciblée
#   variante > remise ciblée produit > remise globale `discount_percent`), sans
#   empilement.
# - Rétro-compatibilité : pour les lignes sans aucune remise ciblée, on applique
#   la remise globale (max des `discount_percent`) sur leur sous-total agrégé et
#   on arrondit une seule fois — comportement identique à l'existant.
# - Une remise en € ne peut jamais rendre le prix négatif (plancher 0, plafond prix).
class GroupDiscountService
  def initialize(customer)
    # `groups` et `group_product_discounts` sont chargés paresseusement ; les
    # appelants qui bouclent sur plusieurs clients doivent précharger
    # (`includes(groups: :group_product_discounts)`) pour éviter le N+1.
    @groups = customer ? customer.groups.to_a : []
  end

  # Remise totale (en cents) pour une collection de lignes.
  # `lines` : tableau de hashes { variant:, qty: }.
  def total_discount_cents(lines)
    return 0 if @groups.empty?

    non_targeted_gross = 0
    discount = 0

    lines.each do |line|
      variant = line[:variant]
      qty = line[:qty].to_i
      next if variant.nil? || qty <= 0

      if targeted?(variant)
        discount += unit_discount_cents(variant) * qty
      else
        non_targeted_gross += variant.price_cents * qty
      end
    end

    discount + self.class.percent_discount_cents(non_targeted_gross, global_percent)
  end

  # Remise (en cents) pour UNE unité d'une variante, meilleure offre tous groupes
  # confondus. Sert au préchargement côté admin (aperçu JS) pour les variantes
  # touchées par une remise ciblée.
  def unit_discount_cents(variant)
    return 0 if @groups.empty?

    @groups.map { |group| group_unit_discount_cents(group, variant) }.max
  end

  # Une variante est-elle visée par une remise ciblée d'au moins un groupe ?
  def targeted?(variant)
    @groups.any? { |group| group.discount_for(variant).present? }
  end

  # Map { variant_id => réduction unitaire en cents } pour toutes les variantes
  # touchées par une remise ciblée (variante directe ou produit → ses variantes).
  # Utilisée pour l'aperçu temps réel du formulaire de commande admin.
  def targeted_unit_discounts(variant_lookup)
    result = {}
    variant_lookup.each_value do |variant|
      result[variant.id] = unit_discount_cents(variant) if targeted?(variant)
    end
    result
  end

  # Pourcentage global appliqué aux lignes non ciblées (max des groupes).
  def global_percent
    @groups.map(&:discount_percent).max || 0
  end

  def self.percent_discount_cents(gross_cents, percent)
    return 0 unless percent.to_i.positive?

    (gross_cents * percent / 100.0).round
  end

  private

  def group_unit_discount_cents(group, variant)
    rule = group.discount_for(variant)
    if rule
      rule.unit_discount_cents(variant.price_cents)
    else
      self.class.percent_discount_cents(variant.price_cents, group.discount_percent)
    end
  end
end
