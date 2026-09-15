class Product < ApplicationRecord
  has_soft_deletion

  enum :category, { breads: 0, dough_balls: 1 }
  # Catégorie interne (usage comptable/reporting) : distingue la production
  # maison (boulangerie) des reventes (épicerie, traiteur, etc.).
  enum :internal_category, { boulangerie: 0, epicerie: 1, traiteur: 2, autre: 3 }, prefix: true

  # Rôle dans le dispositif « Pizza party privée » (#68).
  # - none    : produit ordinaire, sans lien avec les pizza partys.
  # - party   : produit « Pizza party privée – Nombre de personnes » (1 boule /
  #             personne) ; sa présence au panier déclenche le forfait.
  # - forfait : le forfait Pizza party (40 €), compté UNE seule fois par
  #             commande, ajouté par le service de demande (#pizza-parties).
  # - public_party : produit « Pizza party publique » (variantes adulte / enfant,
  #                  #pizza-parties). Pas de forfait ; barème compta dédié
  #                  (PublicPartyRevenueService, base 4S par variante).
  enum :pizza_party_role, { none: 0, party: 1, forfait: 2, public_party: 3 }, prefix: true

  has_many :product_variants, dependent: :destroy
  has_many :product_availabilities, through: :product_variants
  has_many :product_images, dependent: :destroy
  has_many :product_flours, dependent: :destroy
  has_many :flours, through: :product_flours
  # Lieux de retrait pour lesquels ce produit N'EST PAS commandable (#152).
  has_many :product_pickup_location_exclusions, dependent: :destroy
  has_many :excluded_pickup_locations, through: :product_pickup_location_exclusions,
                                       source: :pickup_location

  accepts_nested_attributes_for :product_images, allow_destroy: true, reject_if: :reject_empty_image?
  accepts_nested_attributes_for :product_flours, allow_destroy: true

  validates :name, presence: true
  validates :category, presence: true
  validates :internal_category, presence: true
  validates :position, presence: true, numericality: { only_integer: true }
  validates :channel, presence: true, inclusion: { in: %w[store admin] }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(category: :asc, position: :asc, name: :asc) }
  scope :store_channel, -> { where(channel: "store") }
  scope :not_deleted, -> { where(deleted_at: nil) }
  # Le produit forfait de la Pizza party (#68) — un seul attendu en base.
  scope :pizza_party_forfait, -> { where(pizza_party_role: :forfait) }

  # Rôles pizza_party présents dans un panier de session. Seule survivance de
  # l'ancien service de forfait, dont la raison d'être — synchroniser une ligne
  # de forfait dans le panier — a disparu avec la sortie de la party privée du
  # panier (#pizza-parties). La party PUBLIQUE, elle, s'y inscrit encore.
  def self.pizza_party_roles_in_cart(cart)
    variant_ids = Array(cart).map { |item| item["product_variant_id"].to_s }.reject(&:blank?).uniq
    return [] if variant_ids.empty?

    ProductVariant.joins(:product).where(id: variant_ids)
                  .distinct.pluck(Product.arel_table[:pizza_party_role])
                  .map { |role| role.is_a?(Integer) ? pizza_party_roles.key(role) : role.to_s }
  end

  # Variante boutique d'un produit Pizza party, par rôle (`:party`, `:forfait`,
  # `:public_party`). SOURCE UNIQUE de cette recherche. Renvoie nil si le produit
  # n'est pas configuré (base sans seeds) ; les appelants le signalent plutôt que
  # de planter.
  def self.pizza_party_variant(role)
    product = not_deleted.find_by(pizza_party_role: role)
    return nil unless product

    product.product_variants.active.store_channel.first || product.product_variants.first
  end

  # Vrai si ce produit est commandable pour le lieu de retrait donné (#152).
  # `nil` (aucun lieu) → commandable (pas de contrainte). Un produit sans aucune
  # exclusion est toujours commandable.
  def orderable_at?(pickup_location)
    return true if pickup_location.nil?

    excluded_pickup_location_ids.exclude?(pickup_location.id)
  end

  def display_name
    name
  end

  def flour_composition_label
    return "Aucune" if product_flours.empty?

    product_flours.includes(:flour).map { |pf| "#{pf.flour.name} #{pf.percentage} %" }.join(", ")
  end

  # Une ligne de ce produit est-elle un PÂTON, soit une boule par personne ?
  # Vrai pour les deux formes de party — la privée (« Nombre de personnes ») et
  # la publique (inscriptions adulte/enfant, un convive = une boule, cf.
  # PublicPartyRevenueService qui compte une personne par unité) — jamais pour le
  # forfait, unique par commande quel que soit le nombre de convives.
  def paton_line?
    pizza_party_role_party? || pizza_party_role_public_party?
  end

  # Ce produit peut-il être ajouté au PANIER ? (#pizza-parties)
  #
  # Une party PRIVÉE ne se réserve plus par le panier : elle passe par une
  # demande, validée par la boulangerie. Le refus vit ICI et non dans une garde
  # de contrôleur, parce que `POST /cart/add` accepte n'importe quel
  # `product_variant_id` : un pâton privé glissé dans un panier de pain
  # produirait une commande datée par fournée que l'index des parties et le
  # barème boulangers compteraient comme une party.
  def cartable?
    !pizza_party_role_party? && !pizza_party_role_forfait?
  end

  # Un sac à pain est compté d'office pour chaque unité de PAIN PRODUIT (#52) :
  # catégorie « breads » et production maison (internal_category « boulangerie »).
  # Les pâtons (pâte à pizza, catégorie dough_balls) et les reventes (épicerie,
  # traiteur…) n'entraînent aucun coût de sac.
  def incurs_bag_cost?
    breads? && internal_category_boulangerie?
  end

  private

  def reject_empty_image?(attributes)
    Rails.logger.debug "reject_empty_image? called with: #{attributes.inspect}"

    # Don't reject if _destroy is set to true or '1' (we want to process deletions)
    destroy_value = attributes["_destroy"] || attributes[:_destroy]
    return false if destroy_value == true || destroy_value == "1" || destroy_value == 1

    # For existing records (with id), don't reject (allow updates without new image)
    return false if attributes["id"].present?

    # For new records, reject if no image is provided
    # Check both string and symbol keys
    image_value = attributes["image"] || attributes[:image]

    Rails.logger.debug "Image value: #{image_value.inspect}, blank?: #{image_value.blank?}"

    # Reject if image is blank or nil
    image_value.blank?
  end
end
