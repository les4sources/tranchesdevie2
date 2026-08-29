# Couche données d'une facture, indépendante du rendu PDF (#38).
#
# Sépare la logique « quelles lignes, dans quel ordre, avec quels libellés »
# du rendu Prawn lui-même, de sorte que le contenu soit testable sans parser un
# PDF. Le service de génération PDF consomme ce presenter.
#
# Pour une facture de **période** (mensuelle groupée, clients pro), les
# commandes sont regroupées **par jour de cuisson** (`bake_day`), chaque jour
# identifiable (cf. #27).
class InvoicePresenter
  # Une ligne d'article de la facture.
  Line = Struct.new(
    :label,          # « Produit — variante »
    :quantity,
    :unit_price_cents,
    :total_cents,
    keyword_init: true
  )

  # Un groupe « jour de cuisson » (facture de période).
  #
  # `gross_cents` est le montant AU PRIX STANDARD (Σ qté × prix unitaire de la
  # variante), `total_cents` le montant réellement dû. L'écart entre les deux
  # est la remise client effectivement appliquée le jour de la commande.
  BakeDayGroup = Struct.new(
    :baked_on,
    :order_numbers,
    :lines,
    :gross_cents,
    :total_cents,
    keyword_init: true
  ) do
    def discount_cents = InvoicePresenter.discount_cents(gross_cents, total_cents)
    def discount_percent = InvoicePresenter.discount_percent(gross_cents, total_cents)
    def discount_applied? = discount_cents.positive?
  end

  # Remise = montant au prix standard - montant dû, jamais négative.
  #
  # Elle est DÉDUITE des montants figés (les lignes portent le prix standard,
  # `orders.total_cents` porte le net — cf. OrderCreationService), et non
  # recalculée depuis les groupes actuels du client : un relevé réédité un an
  # plus tard doit montrer la remise du jour de la commande, pas celle
  # d'aujourd'hui.
  def self.discount_cents(gross_cents, net_cents)
    [ gross_cents.to_i - net_cents.to_i, 0 ].max
  end

  # Taux effectif de la remise, en pourcent (une décimale). « Effectif » parce
  # qu'il peut mêler la remise globale du groupe et des remises ciblées par
  # produit ou variante (#87) : on affiche ce qui a réellement été appliqué.
  def self.discount_percent(gross_cents, net_cents)
    return 0.0 if gross_cents.to_i.zero?

    (discount_cents(gross_cents, net_cents) * 100.0 / gross_cents).round(1)
  end

  def initialize(invoice)
    @invoice = invoice
  end

  attr_reader :invoice

  def number
    invoice.number
  end

  def issued_on
    invoice.issued_on
  end

  def period?
    invoice.period?
  end

  def period_label
    return nil unless period?

    "#{I18n.l(invoice.period_start)} – #{I18n.l(invoice.period_end)}"
  end

  # Coordonnées client, prêtes à l'affichage (lignes non vides).
  def customer_address_lines
    customer = invoice.customer
    [
      customer.full_name,
      customer.email.presence,
      customer.phone_e164.presence
    ].compact
  end

  # Identifiant(s) de connexion à rappeler au client sur le relevé : le numéro
  # de téléphone et/ou l'e-mail, selon ce dont il dispose (#38). Sert à lui
  # indiquer avec quoi se connecter pour retrouver le détail en ligne.
  def login_identifiers
    customer = invoice.customer
    [
      customer.phone_e164.presence,
      customer.email.presence
    ].compact
  end

  # Lignes « à plat » (facture commande unique, ou usage tabulaire simple).
  def lines
    ordered_orders.flat_map { |order| lines_for(order) }
  end

  # Groupes par jour de cuisson (facture de période). Chaque groupe est
  # identifiable par sa date et les numéros de commande qu'il couvre.
  def bake_day_groups
    ordered_orders
      .group_by { |order| order.bake_day.baked_on }
      .sort_by { |baked_on, _| baked_on }
      .map do |baked_on, orders|
        group_lines = orders.flat_map { |order| lines_for(order) }
        BakeDayGroup.new(
          baked_on: baked_on,
          order_numbers: orders.map(&:order_number),
          lines: group_lines,
          gross_cents: group_lines.sum(&:total_cents),
          total_cents: orders.sum(&:total_cents)
        )
      end
  end

  def subtotal_cents
    invoice.subtotal_cents
  end

  def vat_cents
    invoice.vat_cents
  end

  def vat_rate
    invoice.vat_rate
  end

  def vat_applied?
    invoice.vat_applied?
  end

  def total_cents
    invoice.total_cents
  end

  # Montant du relevé AU PRIX STANDARD, remise non déduite : Σ des lignes, qui
  # portent toutes le prix catalogue de la variante.
  def gross_cents
    lines.sum(&:total_cents)
  end

  # Remise client effectivement appliquée sur l'ensemble du relevé.
  def discount_cents
    self.class.discount_cents(gross_cents, total_cents)
  end

  def discount_percent
    self.class.discount_percent(gross_cents, total_cents)
  end

  def discount_applied?
    discount_cents.positive?
  end

  private

  def ordered_orders
    invoice.orders
           .includes(:bake_day, order_items: { product_variant: :product })
           .sort_by { |order| [ order.bake_day.baked_on, order.order_number ] }
  end

  def lines_for(order)
    order.order_items.map do |item|
      Line.new(
        label: item.full_name,
        quantity: item.qty,
        unit_price_cents: item.unit_price_cents,
        total_cents: item.subtotal_cents
      )
    end
  end
end
