require "prawn"
require "prawn/table"

# Feuille d'émargement d'un point de retrait pour une fournée (#148).
#
# Sert aux boulangers le jour du retrait : une ligne par client, avec le détail
# de sa commande et une case à cocher AU STYLO quand il vient récupérer. Il n'y a
# volontairement aucun pointage en ligne : le PDF ne change aucun statut.
#
# Même contrat public qu'InvoicePdfService (`#render` → String binaire,
# `#filename`) et mêmes constantes de charte.
#
# Usage :
#   pdf = PickupSheetPdfService.new(bake_day, pickup_location).render
class PickupSheetPdfService
  BRAND_COLOR = "7C2D12".freeze   # terracotta (cf. e-mails / factures)
  MUTED_COLOR = "8A8178".freeze
  LIGHT_FILL = "FAF7F2".freeze

  DOCUMENT_TITLE = "Feuille de retrait".freeze

  # Mêmes statuts que le tableau de bord de fournée : ce qui est réellement
  # produit et donc à remettre au client.
  PRODUCTION_STATUSES = %i[unpaid paid ready picked_up planned].freeze

  def initialize(bake_day, pickup_location)
    @bake_day = bake_day
    @pickup_location = pickup_location
  end

  def render
    document.render
  end

  def filename
    "retrait-#{@pickup_location.name.parameterize}-#{@bake_day.baked_on.strftime('%Y-%m-%d')}.pdf"
  end

  # Commandes de CE lieu pour CETTE fournée, triées par nom de client.
  def orders
    @orders ||= @bake_day.orders
      .where(pickup_location_id: @pickup_location.id, status: PRODUCTION_STATUSES)
      .includes(:customer, order_items: { product_variant: :product })
      .to_a
      .sort_by { |order| customer_name(order).downcase }
  end

  private

  def document
    pdf = Prawn::Document.new(page_size: "A4", margin: 40)
    pdf.font_families.update(default: pdf.font_families["Helvetica"])

    render_header(pdf)
    render_table(pdf)
    render_footer(pdf)

    pdf
  end

  def render_header(pdf)
    pdf.fill_color BRAND_COLOR
    pdf.text BakeryDetails::NAME, size: 22, style: :bold
    pdf.fill_color "000000"
    pdf.move_down 6

    pdf.text DOCUMENT_TITLE, size: 16, style: :bold
    pdf.move_down 8

    pdf.text @pickup_location.name, size: 14, style: :bold
    if @pickup_location.description.present?
      pdf.fill_color MUTED_COLOR
      pdf.text @pickup_location.description, size: 9
      pdf.fill_color "000000"
    end

    pdf.move_down 4
    pdf.text "Fournée du #{I18n.l(@bake_day.baked_on)}", size: 11
    pdf.move_down 14
  end

  def render_table(pdf)
    if orders.empty?
      pdf.fill_color MUTED_COLOR
      pdf.text "Aucune commande à retirer sur ce point pour cette fournée.", size: 10
      pdf.fill_color "000000"
      return
    end

    # 1re colonne : la case à cocher. Volontairement sans libellé — les polices
    # PDF intégrées (Windows-1252) ne portent pas de glyphe « ✓ ».
    header = [ "", "Client", "Téléphone", "Commande", "Total" ]
    body = orders.map do |order|
      [ "", customer_name(order), order.customer.phone_e164.to_s, items_label(order), euros(order.total_cents) ]
    end

    pdf.table(
      [ header ] + body,
      width: pdf.bounds.width,
      header: true,
      column_widths: column_widths(pdf),
      cell_style: { size: 9, padding: [ 6, 6 ], borders: [ :bottom ], border_color: "EEEEEE" }
    ) do |t|
      t.row(0).font_style = :bold
      t.row(0).background_color = LIGHT_FILL
      t.row(0).text_color = "333333"
      t.column(4).align = :right

      # Case à cocher vide : le boulanger coche au stylo au moment du retrait.
      t.column(0).align = :center
      t.rows(1..-1).column(0).borders = [ :bottom, :left, :right, :top ]
      t.rows(1..-1).column(0).border_color = "999999"
      t.rows(1..-1).column(0).height = 22
    end
  end

  def column_widths(pdf)
    total = pdf.bounds.width
    [ 24, 110, 90, total - 224 - 70, 70 ]
  end

  def render_footer(pdf)
    pdf.move_down 18
    pdf.fill_color MUTED_COLOR
    pdf.text "#{orders.size} commande(s) · Cocher la case à la remise de la commande.", size: 9
    pdf.fill_color "000000"
  end

  def customer_name(order)
    order.customer.full_name.presence || "Client ##{order.customer_id}"
  end

  # Détail de la commande : « 2 × Pain de campagne (1 kg) ».
  def items_label(order)
    order.order_items.map do |item|
      variant = item.product_variant
      product_name = variant.product&.name || "Produit supprimé"
      "#{item.qty} × #{product_name} (#{variant.name})"
    end.join("\n")
  end

  def euros(cents)
    formatted = format("%.2f", cents / 100.0).tr(".", ",")
    "#{formatted} €"
  end
end
