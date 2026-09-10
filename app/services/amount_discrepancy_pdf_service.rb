require "prawn"
require "prawn/table"

# PDF de la liste des **écarts de montant** — les commandes dont le total ne se
# déduit pas de leur détail (#retour Manon). Destiné à la compta : Manon
# l'imprime, fait le point commande par commande, et corrige dans l'admin.
#
# Même charte que le relevé de commandes (InvoicePdfService), mais c'est un
# document INTERNE : pas de coordonnées client, pas de QR, pas de mention
# commerciale.
#
# Usage :
#   report = AmountDiscrepancyService.new.call
#   pdf = AmountDiscrepancyPdfService.new(report).render   # => String binaire
class AmountDiscrepancyPdfService
  BRAND_COLOR = "7C2D12".freeze   # terracotta (cf. relevés et e-mails)
  MUTED_COLOR = "8A8178".freeze
  LIGHT_FILL = "FAF7F2".freeze
  DANGER_COLOR = "B91C1C".freeze

  DOCUMENT_TITLE = "Écarts de montant".freeze

  ABOVE_TITLE = "Montant au-dessus du détail".freeze
  ABOVE_HINT = "Aucune remise ne peut rendre une commande plus chère que la somme de ses lignes : " \
               "ces montants sont à corriger. Sur le relevé du client, l'écart apparaît en « Ajustement ».".freeze

  BELOW_TITLE = "Montant sous le détail, sans remise applicable".freeze
  BELOW_HINT = "Ces clients n'appartiennent à aucun groupe de remise : rien dans le barème " \
               "n'explique la réduction. À relire — prix convenu de vive voix, ou montant saisi de travers.".freeze

  EMPTY_MESSAGE = "Aucun écart à relire : chaque commande analysée porte un montant qui se déduit de son détail.".freeze

  def initialize(report, generated_on: Date.current)
    @report = report
    @generated_on = generated_on
  end

  def render
    document.render
  end

  def filename
    "ecarts-de-montant-#{@generated_on.strftime('%Y-%m-%d')}.pdf"
  end

  private

  def document
    pdf = Prawn::Document.new(page_size: "A4", margin: 40)
    pdf.font_families.update(default: pdf.font_families["Helvetica"])

    render_header(pdf)
    render_summary(pdf)

    if @report.any?
      render_section(pdf, ABOVE_TITLE, ABOVE_HINT, @report.above)
      render_section(pdf, BELOW_TITLE, BELOW_HINT, @report.unexplained_below)
    else
      pdf.move_down 8
      pdf.text EMPTY_MESSAGE, size: 10
    end

    render_method_note(pdf)
    pdf
  end

  def render_header(pdf)
    pdf.fill_color BRAND_COLOR
    pdf.text BakeryDetails::NAME, size: 22, style: :bold
    pdf.fill_color MUTED_COLOR
    pdf.text BakeryDetails::TAGLINE, size: 9
    pdf.fill_color "000000"
    pdf.move_down 6
    pdf.text DOCUMENT_TITLE, size: 16, style: :bold
    pdf.fill_color MUTED_COLOR
    pdf.text "Document interne — édité le #{I18n.l(@generated_on)}", size: 9
    pdf.fill_color "000000"
    pdf.move_down 14
  end

  # Le compte complet : combien de commandes passées au crible, combien
  # d'écarts à relire, et combien d'écarts sont couverts par une remise de
  # groupe (donc non listés). Sans ce dernier chiffre, une liste courte
  # laisserait croire que le balayage est passé à côté de quelque chose.
  def render_summary(pdf)
    rows = [
      [ "Commandes analysées", @report.scanned_count.to_s ],
      [ "Écarts à relire", @report.total_count.to_s ],
      [ "Écarts couverts par une remise de groupe (non listés)", @report.covered_by_group_count.to_s ]
    ]

    pdf.table(
      rows,
      width: pdf.bounds.width,
      cell_style: { borders: [ :bottom ], border_color: "EEEEEE", padding: [ 4, 6 ], size: 10 }
    ) do |t|
      t.column(0).font_style = :bold
      t.column(0).width = 320
      t.column(1).align = :right
    end
    pdf.move_down 16
  end

  def render_section(pdf, title, hint, rows)
    pdf.fill_color BRAND_COLOR
    pdf.text "#{title} — #{rows.size}", size: 12, style: :bold
    pdf.fill_color MUTED_COLOR
    pdf.text hint, size: 8.5
    pdf.fill_color "000000"
    pdf.move_down 6

    if rows.empty?
      pdf.text "Rien à signaler.", size: 9, style: :italic
      pdf.move_down 16
      return
    end

    render_table(pdf, rows)
    pdf.move_down 16
  end

  def render_table(pdf, rows)
    header = [ "Date", "N° commande", "Client", "Détail", "Somme des lignes", "Montant enregistré", "Écart" ]
    body = rows.map do |row|
      [
        I18n.l(row.order_date),
        row.order.order_number,
        row.customer.full_name.to_s.squish,
        detail_for(row.order),
        euros(row.gross_cents),
        euros(row.total_cents),
        signed_euros(row.delta_cents)
      ]
    end

    pdf.table(
      [ header ] + body,
      width: pdf.bounds.width,
      header: true,
      column_widths: column_widths(pdf),
      cell_style: { size: 8, padding: [ 5, 5 ], borders: [ :bottom ], border_color: "EEEEEE" }
    ) do |t|
      t.row(0).font_style = :bold
      t.row(0).background_color = LIGHT_FILL
      t.row(0).text_color = "333333"
      t.columns(4..6).align = :right
      t.column(6).font_style = :bold
      t.column(6).text_color = DANGER_COLOR
      t.row(0).text_color = "333333"
    end
  end

  # Le détail des lignes, pour que Manon retrouve l'erreur sans rouvrir l'écran :
  # c'est la comparaison « 18 × 4,50 € » contre « 90,00 € » qui saute aux yeux.
  def detail_for(order)
    order.order_items.map do |item|
      "#{item.qty} × #{item.full_name} à #{euros(item.unit_price_cents)}"
    end.join("\n")
  end

  def column_widths(pdf)
    total = pdf.bounds.width
    fixed = 52 + 78 + 72 + 62 + 68 + 48
    [ 52, 78, 72, total - fixed, 62, 68, 48 ]
  end

  # Rappel de méthode : ce que le balayage couvre, et la limite qu'il assume.
  def render_method_note(pdf)
    pdf.move_down 10
    pdf.stroke_color "EEEEEE"
    pdf.stroke_horizontal_rule
    pdf.stroke_color "000000"
    pdf.move_down 10

    pdf.fill_color MUTED_COLOR
    pdf.text "Comment cette liste est établie", size: 9, style: :bold
    pdf.move_down 3
    pdf.text method_note, size: 8, leading: 1.5
    pdf.fill_color "000000"
  end

  def method_note
    [
      "Chaque commande est comparée à la somme de ses lignes, au prix figé le jour de la commande. " \
      "Les commandes annulées, en attente de paiement, celles des Pizza parties (vendues au forfait) " \
      "et celles des fournées brouillon sont hors périmètre.",
      "Le taux de remise appliqué le jour de la commande n'est pas conservé, et l'appartenance d'un client " \
      "à ses groupes évolue. Les commandes sous leur détail chez un client qui bénéficie d'une remise de " \
      "groupe ne sont donc pas listées : les comparer au barème d'aujourd'hui produirait surtout de fausses " \
      "alertes. Leur nombre figure en tête de ce document."
    ].join("\n\n")
  end

  def euros(cents)
    "#{format('%.2f', cents.to_i / 100.0).tr('.', ',')} €"
  end

  def signed_euros(cents)
    "#{cents.to_i.positive? ? '+' : '-'}#{euros(cents.to_i.abs)}"
  end
end
