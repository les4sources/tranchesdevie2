# Repère les commandes dont le **montant total ne se déduit plus de leur détail**
# (#retour Manon).
#
# `orders.total_cents` est un montant figé, saisi à la main dans le formulaire
# admin. Il pouvait rester en arrière d'une correction de quantité — c'est ainsi
# qu'un relevé a affiché « Sous-total cuisson : 90,00 € » sous 18 pains à
# 4,50 €. Ce service produit la liste à relire.
#
# Deux familles seulement, toutes deux **inexplicables par un barème** :
#
#   1. **Montant au-dessus du détail** — anomalie certaine : aucune remise ne
#      peut rendre une commande PLUS chère que la somme de ses lignes.
#   2. **Montant sous le détail chez un client sans remise** — le client
#      n'appartient à aucun groupe, donc aucun barème n'accorde cette réduction.
#
# Ce qui n'est PAS listé, volontairement : les commandes sous leur détail chez un
# client qui bénéficie d'une remise de groupe. Le taux appliqué le jour de la
# commande n'est pas conservé, et l'appartenance aux groupes évolue — les
# comparer au barème d'aujourd'hui produirait des centaines de fausses alertes
# (des clients entrés dans un groupe APRÈS leurs premières commandes). Leur
# nombre est reporté en tête de relevé pour que le compte soit complet.
class AmountDiscrepancyService
  # Statuts hors périmètre : une commande annulée ne se facture pas, une
  # commande `pending` est une réservation transitoire du paiement en ligne.
  EXCLUDED_STATUSES = %w[cancelled pending].freeze

  Row = Struct.new(:order, :gross_cents, keyword_init: true) do
    def total_cents = order.total_cents

    # Écart avec la somme des lignes. Positif = montant au-dessus du détail.
    def delta_cents = total_cents - gross_cents

    def customer = order.customer
    def order_date = order.bake_day&.baked_on || order.created_at.to_date
  end

  Report = Struct.new(
    :above, :unexplained_below, :scanned_count, :covered_by_group_count,
    keyword_init: true
  ) do
    def any? = above.any? || unexplained_below.any?
    def total_count = above.size + unexplained_below.size
  end

  def call
    above = []
    unexplained_below = []
    covered = 0
    scanned = 0

    scoped_orders.find_each do |order|
      gross = gross_cents_for(order)
      next if gross.zero?

      scanned += 1
      next if order.total_cents == gross

      row = Row.new(order: order, gross_cents: gross)

      if row.delta_cents.positive?
        above << row
      elsif discount_group?(order.customer)
        covered += 1
      else
        unexplained_below << row
      end
    end

    Report.new(
      above: sort_rows(above),
      unexplained_below: sort_rows(unexplained_below),
      scanned_count: scanned,
      covered_by_group_count: covered
    )
  end

  private

  # Périmètre : les commandes de pain réellement comptables. Les commandes
  # `party` sont exclues — elles sont vendues au forfait (barème party), leur
  # total ne prétend pas se déduire de leurs lignes. Les fournées brouillon sont
  # exclues aussi : un brouillon est une calculatrice de boulanger, il n'entre
  # dans aucun chiffre.
  def scoped_orders
    Order
      .where.not(status: EXCLUDED_STATUSES)
      .where.not(source: :party)
      .where(bake_day: BakeDay.where(draft: false))
      .includes(:bake_day, { customer: :groups }, order_items: { product_variant: :product })
      .order(created_at: :desc)
  end

  # Somme des lignes AUX PRIX FIGÉS le jour de la commande — c'est exactement ce
  # que le relevé PDF imprime dans sa colonne « Total ».
  def gross_cents_for(order)
    order.order_items.sum { |item| item.qty.to_i * item.unit_price_cents.to_i }
  end

  # Le client bénéficie-t-il d'une remise (globale ou ciblée) via un groupe ?
  def discount_group?(customer)
    return false if customer.nil?

    customer.groups.any? do |group|
      group.discount_percent.to_i.positive? || group.group_product_discounts.any?
    end
  end

  # Les plus gros écarts d'abord : c'est par là que Manon commence.
  def sort_rows(rows)
    rows.sort_by { |row| [ -row.delta_cents.abs, row.order.order_number ] }
  end
end
