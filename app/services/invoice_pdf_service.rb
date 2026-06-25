require "prawn"
require "prawn/table"

# Génère le PDF d'une facture (#38) avec Prawn (Ruby pur, aucun binaire système).
#
# Contenu : coordonnées boulangerie + client, numéro de facture, date, détail
# des articles (nom produit + variante, quantité, prix unitaire, total ligne),
# total HT/TVA/TTC (TVA paramétrable — note TVA #38).
#
# Pour une facture de **période** (mensuelle groupée, clients pro), les
# commandes sont regroupées **par jour de cuisson**, chaque jour identifiable
# (cf. #27).
#
# Usage :
#   pdf = InvoicePdfService.new(invoice).render   # => String binaire (PDF)
class InvoicePdfService
  BRAND_COLOR = "7C2D12".freeze   # terracotta (cf. e-mails)
  MUTED_COLOR = "8A8178".freeze
  LIGHT_FILL = "FAF7F2".freeze

  def initialize(invoice)
    @invoice = invoice
    @presenter = InvoicePresenter.new(invoice)
  end

  # Renvoie le PDF sous forme de chaîne binaire.
  def render
    document.render
  end

  # Nom de fichier suggéré pour le téléchargement.
  def filename
    "facture-#{@invoice.number}.pdf"
  end

  private

  def document
    pdf = Prawn::Document.new(page_size: "A4", margin: 40)
    pdf.font_families.update(default: pdf.font_families["Helvetica"])

    render_header(pdf)
    render_parties(pdf)
    render_meta(pdf)
    render_body(pdf)
    render_totals(pdf)
    render_footer(pdf)

    pdf
  end

  def render_header(pdf)
    pdf.fill_color BRAND_COLOR
    pdf.text BakeryDetails::NAME, size: 22, style: :bold
    pdf.fill_color MUTED_COLOR
    pdf.text BakeryDetails::TAGLINE, size: 9, style: :normal
    pdf.fill_color "000000"
    pdf.move_down 6
    pdf.text "FACTURE", size: 16, style: :bold
    pdf.move_down 12
  end

  def render_parties(pdf)
    bakery = BakeryDetails.address_lines.join("\n")
    customer = @presenter.customer_address_lines.join("\n")

    pdf.table(
      [ [ box("Émetteur", bakery), box("Client", customer) ] ],
      width: pdf.bounds.width,
      column_widths: [ pdf.bounds.width / 2, pdf.bounds.width / 2 ],
      cell_style: { borders: [], padding: [ 0, 8, 0, 0 ] }
    )
    pdf.move_down 14
  end

  def box(title, content)
    "#{title}\n#{content}"
  end

  def render_meta(pdf)
    rows = [
      [ "Numéro de facture", @presenter.number ],
      [ "Date d'émission", I18n.l(@presenter.issued_on) ]
    ]
    rows << [ "Période facturée", @presenter.period_label ] if @presenter.period?

    pdf.table(
      rows,
      width: pdf.bounds.width,
      cell_style: { borders: [ :bottom ], border_color: "EEEEEE", padding: [ 4, 6 ], size: 10 }
    ) do |t|
      t.column(0).font_style = :bold
      t.column(0).width = 160
    end
    pdf.move_down 16
  end

  def render_body(pdf)
    if @presenter.period?
      render_grouped_body(pdf)
    else
      render_flat_table(pdf, @presenter.lines)
    end
  end

  # Facture de période : un sous-tableau par jour de cuisson, identifiable.
  def render_grouped_body(pdf)
    @presenter.bake_day_groups.each do |group|
      pdf.fill_color BRAND_COLOR
      title = "Cuisson du #{I18n.l(group.baked_on)}"
      title += " — #{group.order_numbers.join(', ')}" if group.order_numbers.any?
      pdf.text title, size: 11, style: :bold
      pdf.fill_color "000000"
      pdf.move_down 4

      render_flat_table(pdf, group.lines)

      pdf.move_down 4
      pdf.text "Sous-total cuisson : #{euros(group.total_cents)}", size: 9, style: :bold, align: :right
      pdf.move_down 14
    end
  end

  def render_flat_table(pdf, lines)
    header = [ "Article", "Qté", "Prix unitaire", "Total" ]
    body = lines.map do |line|
      [ line.label, line.quantity.to_s, euros(line.unit_price_cents), euros(line.total_cents) ]
    end

    pdf.table(
      [ header ] + body,
      width: pdf.bounds.width,
      header: true,
      column_widths: column_widths(pdf),
      cell_style: { size: 9, padding: [ 5, 6 ], borders: [ :bottom ], border_color: "EEEEEE" }
    ) do |t|
      t.row(0).font_style = :bold
      t.row(0).background_color = LIGHT_FILL
      t.row(0).text_color = "333333"
      t.columns(1..3).align = :right
    end
  end

  def column_widths(pdf)
    total = pdf.bounds.width
    [ total - 210, 50, 80, 80 ]
  end

  def render_totals(pdf)
    pdf.move_down 6
    rows = []
    if @presenter.vat_applied?
      rows << [ "Total HT", euros(@presenter.subtotal_cents) ]
      rows << [ "TVA (#{format('%g', @presenter.vat_rate)} %)", euros(@presenter.vat_cents) ]
      rows << [ "Total TTC", euros(@presenter.total_cents) ]
    else
      rows << [ "Total", euros(@presenter.total_cents) ]
    end

    pdf.table(
      rows,
      position: :right,
      column_widths: [ 120, 90 ],
      cell_style: { size: 10, padding: [ 4, 6 ], borders: [] }
    ) do |t|
      t.column(0).font_style = :bold
      t.columns(0..1).align = :right
      t.row(rows.size - 1).font_style = :bold
      t.row(rows.size - 1).size = 12
    end
  end

  def render_footer(pdf)
    pdf.move_down 24
    pdf.fill_color MUTED_COLOR
    pdf.text "Merci de votre confiance.", size: 9, align: :center
    pdf.text [ BakeryDetails::NAME, BakeryDetails::EMAIL ].join(" · "), size: 8, align: :center
    pdf.fill_color "000000"
  end

  def euros(cents)
    formatted = format("%.2f", cents / 100.0).tr(".", ",")
    "#{formatted} €"
  end
end
