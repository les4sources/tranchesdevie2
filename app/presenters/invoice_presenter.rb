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
  BakeDayGroup = Struct.new(
    :baked_on,
    :order_numbers,
    :lines,
    :total_cents,
    keyword_init: true
  )

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
