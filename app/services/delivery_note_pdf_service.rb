require "prawn"
require "prawn/table"

# Génère le **bon de livraison** PDF d'une commande avec Prawn (Ruby pur), à
# côté du relevé de commandes (InvoicePdfService) dans admin > Facturation.
#
# Le relevé accompagne la facture ; le bon de livraison accompagne les pains :
# il part avec la marchandise et le client le signe à la réception. D'où son
# contenu :
#   - numéro de bon, numéro de commande, date de production (jour de cuisson) ;
#   - coordonnées de la boulangerie (Les 4 Sources) et du client ;
#   - lieu de retrait / livraison ;
#   - détail des pains : article, quantité, prix unitaire, total ligne ;
#   - nombre total de pains et coût total (remise ou ajustement exposés sur leur
#     propre ligne, comme sur le relevé) ;
#   - remarque du client, s'il y en a une ;
#   - cadre de réception : « Livré par » / « Reçu par », nom, date, signature.
#
# Comme le relevé, ce n'est PAS une facture : pas de bloc TVA / HT-TTC.
#
# Usage :
#   service = DeliveryNotePdfService.new(order)
#   service.render    # => String binaire (PDF)
#   service.filename  # => "bon-de-livraison-BL-20260512-0001.pdf"
class DeliveryNotePdfService
  BRAND_COLOR = InvoicePdfService::BRAND_COLOR   # terracotta
  MUTED_COLOR = InvoicePdfService::MUTED_COLOR
  LIGHT_FILL = InvoicePdfService::LIGHT_FILL     # crème
  BORDER_COLOR = "E7DFD3".freeze
  TEXT_COLOR = "2B2622".freeze

  DOCUMENT_TITLE = "Bon de livraison".freeze
  LOGO_PATH = Rails.root.join("app/assets/images/logo-les-4-sources.png").freeze
  LOGO_SIZE = 46

  def initialize(order)
    @order = order
  end

  def render
    document.render
  end

  def filename
    "bon-de-livraison-#{number}.pdf"
  end

  # « BL-20260512-0001 » : dérivé du numéro de commande (TV-YYYYMMDD-NNNN), donc
  # stable d'un téléchargement à l'autre sans rien persister.
  def number
    "BL-#{@order.order_number.delete_prefix('TV-')}"
  end

  private

  def document
    pdf = Prawn::Document.new(page_size: "A4", margin: [ 36, 40, 50, 40 ], info: { Title: "#{DOCUMENT_TITLE} #{number}" })
    pdf.font_families.update(default: pdf.font_families["Helvetica"])
    pdf.fill_color TEXT_COLOR

    render_header(pdf)
    render_key_facts(pdf)
    render_parties(pdf)
    render_items(pdf)
    render_totals(pdf)
    render_customer_note(pdf)
    render_reception(pdf)
    render_footer(pdf)

    pdf
  end

  # Bandeau : logo + nom de la boulangerie à gauche, titre du document à droite.
  def render_header(pdf)
    top = pdf.cursor

    pdf.image LOGO_PATH.to_s, at: [ 0, top ], width: LOGO_SIZE, height: LOGO_SIZE if File.exist?(LOGO_PATH)

    pdf.bounding_box([ LOGO_SIZE + 12, top - 4 ], width: 240) do
      pdf.fill_color BRAND_COLOR
      pdf.text BakeryDetails::NAME, size: 20, style: :bold
      pdf.fill_color MUTED_COLOR
      pdf.text "#{BakeryDetails::TAGLINE} · Les 4 Sources", size: 9
    end

    pdf.bounding_box([ pdf.bounds.width - 230, top - 2 ], width: 230) do
      pdf.fill_color TEXT_COLOR
      pdf.text DOCUMENT_TITLE.upcase, size: 18, style: :bold, align: :right, character_spacing: 1
      pdf.fill_color MUTED_COLOR
      pdf.text "N° #{number}", size: 10, align: :right
    end

    pdf.move_cursor_to top - LOGO_SIZE - 14
    pdf.fill_color BRAND_COLOR
    pdf.fill_rectangle [ 0, pdf.cursor ], pdf.bounds.width, 3
    pdf.fill_color TEXT_COLOR
    pdf.move_down 16
  end

  # Trois repères en un coup d'œil : date de production, commande, date d'émission.
  def render_key_facts(pdf)
    facts = [
      [ "Date de production", production_date_label ],
      [ "Commande", @order.order_number ],
      [ "Émis le", I18n.l(Date.current) ]
    ]

    cells = facts.map do |label, value|
      { content: "<font size='8'><color rgb='#{MUTED_COLOR}'>#{label.upcase}</color></font>\n<b>#{escape(value)}</b>",
        inline_format: true }
    end

    pdf.table(
      [ cells ],
      width: pdf.bounds.width,
      cell_style: { background_color: LIGHT_FILL, borders: [], padding: [ 8, 10 ], size: 11, leading: 2 }
    ) do |t|
      t.column(0).width = pdf.bounds.width * 0.42
    end
    pdf.move_down 16
  end

  # Expéditeur / destinataire / lieu de retrait, en trois colonnes.
  def render_parties(pdf)
    columns = [
      party_cell("Boulangerie", BakeryDetails.address_lines),
      party_cell("Client", customer_lines),
      party_cell("Lieu de retrait", pickup_lines)
    ]

    pdf.table(
      [ columns ],
      width: pdf.bounds.width,
      column_widths: Array.new(3, pdf.bounds.width / 3.0),
      cell_style: { borders: [ :top ], border_color: BORDER_COLOR, border_width: 1, padding: [ 8, 10, 4, 0 ], size: 9, leading: 1.5 }
    )
    pdf.move_down 18
  end

  def party_cell(title, lines)
    first, *rest = lines
    content = "<font size='8'><color rgb='#{BRAND_COLOR}'><b>#{title.upcase}</b></color></font>\n"
    content += "<b>#{escape(first)}</b>" if first
    content += "\n" + rest.map { |line| escape(line) }.join("\n") if rest.any?
    { content: content, inline_format: true }
  end

  def render_items(pdf)
    header = [ "Pain", "Quantité", "Prix unitaire", "Total" ]
    body = items.map do |item|
      [ item.full_name, item.qty.to_s, euros(item.unit_price_cents), euros(item.subtotal_cents) ]
    end
    body = [ [ "Aucun article", "", "", "" ] ] if body.empty?

    pdf.table(
      [ header ] + body,
      width: pdf.bounds.width,
      header: true,
      column_widths: [ pdf.bounds.width - 240, 70, 85, 85 ],
      cell_style: { size: 10, padding: [ 7, 8 ], borders: [ :bottom ], border_color: BORDER_COLOR, text_color: TEXT_COLOR }
    ) do |t|
      t.row(0).font_style = :bold
      t.row(0).size = 9
      t.row(0).background_color = BRAND_COLOR
      t.row(0).text_color = "FFFFFF"
      t.row(0).borders = []
      t.columns(1..3).align = :right
      (1...t.row_length).each { |i| t.row(i).background_color = LIGHT_FILL if i.even? }
    end
  end

  # Nombre de pains + coût total. Les lignes portent le prix standard : l'écart
  # avec le montant dû (remise client ou ajustement) a sa propre ligne, comme
  # sur le relevé, pour que le total se déduise toujours du détail.
  def render_totals(pdf)
    pdf.move_down 10

    gross = items.sum(&:subtotal_cents)
    total = @order.total_cents
    discount = InvoicePresenter.discount_cents(gross, total)
    surcharge = InvoicePresenter.surcharge_cents(gross, total)

    rows = [ [ "Nombre de pains", items.sum(&:qty).to_s ] ]
    if discount.positive?
      rows << [ "Total au prix standard", euros(gross) ]
      rows << [ discount_label(InvoicePresenter.discount_percent(gross, total)), "-#{euros(discount)}" ]
    elsif surcharge.positive?
      rows << [ "Total au prix standard", euros(gross) ]
      rows << [ InvoicePdfService::SURCHARGE_LABEL, "+#{euros(surcharge)}" ]
    end

    pdf.table(
      rows,
      position: :right,
      column_widths: [ 160, 95 ],
      cell_style: { size: 10, padding: [ 3, 8 ], borders: [], text_color: TEXT_COLOR }
    ) do |t|
      t.columns(0..1).align = :right
    end

    pdf.move_down 4
    pdf.table(
      [ [ "Total", euros(total) ] ],
      position: :right,
      column_widths: [ 160, 95 ],
      cell_style: { size: 13, padding: [ 7, 8 ], borders: [], font_style: :bold,
                    background_color: BRAND_COLOR, text_color: "FFFFFF" }
    ) do |t|
      t.columns(0..1).align = :right
    end
  end

  def render_customer_note(pdf)
    note = @order.customer_note.to_s.strip
    return if note.empty?

    pdf.move_down 18
    pdf.fill_color BRAND_COLOR
    pdf.text "REMARQUE", size: 8, style: :bold
    pdf.fill_color TEXT_COLOR
    pdf.move_down 3
    pdf.text note, size: 9.5
  end

  # Cadre de réception signé à la livraison. Indivisible : il passe en entier à
  # la page suivante plutôt que d'être coupé.
  RECEPTION_HEIGHT = 120

  def render_reception(pdf)
    pdf.move_down 24
    pdf.start_new_page if pdf.cursor < RECEPTION_HEIGHT + 20

    pdf.fill_color MUTED_COLOR
    pdf.text "Marchandise reçue conforme à ce bon. Toute réserve est à noter ici à la réception.", size: 8.5, style: :italic
    pdf.fill_color TEXT_COLOR
    pdf.move_down 6

    gap = 16
    width = (pdf.bounds.width - gap) / 2.0
    top = pdf.cursor

    [ [ "Livré par", 0 ], [ "Reçu par", width + gap ] ].each do |title, x|
      pdf.bounding_box([ x, top ], width: width, height: RECEPTION_HEIGHT - 20) do
        pdf.stroke_color BORDER_COLOR
        pdf.line_width 1
        pdf.stroke_bounds
        pdf.indent(10, 10) do
          pdf.move_down 8
          pdf.fill_color BRAND_COLOR
          pdf.text title.upcase, size: 8, style: :bold
          pdf.fill_color MUTED_COLOR
          pdf.move_down 6
          [ "Nom", "Date", "Signature" ].each do |field|
            pdf.text "#{field} :", size: 8.5
            pdf.move_down 14
          end
        end
      end
    end
    pdf.fill_color TEXT_COLOR
    pdf.stroke_color "000000"
  end

  # Pied de page sur chaque page : coordonnées et pagination.
  def render_footer(pdf)
    footer = [ BakeryDetails::NAME, "#{BakeryDetails::ADDRESS_LINE}, #{BakeryDetails::POSTAL_CITY}",
               BakeryDetails::EMAIL, BakeryDetails::PHONE_DISPLAY ].join(" · ")

    pdf.repeat(:all) do
      pdf.canvas do
        pdf.fill_color MUTED_COLOR
        pdf.text_box footer, at: [ 40, 30 ], width: pdf.bounds.width - 80, size: 7.5, align: :center
        pdf.fill_color TEXT_COLOR
      end
    end

    pdf.number_pages "<page> / <total>", at: [ pdf.bounds.right - 60, -34 ], width: 60,
      align: :right, size: 7.5, color: MUTED_COLOR
  end

  def items
    @items ||= @order.order_items
                     .includes(product_variant: :product)
                     .sort_by { |item| I18n.transliterate(item.full_name) }
  end

  def production_date_label
    baked_on = @order.bake_day&.baked_on
    return "—" unless baked_on

    I18n.l(baked_on, format: "%A %-d %B %Y").sub(/\A\p{Ll}/, &:upcase)
  end

  def customer_lines
    customer = @order.customer
    [ customer.full_name, customer.email.presence, customer.phone_e164.presence ].compact
  end

  def pickup_lines
    location = @order.pickup_location
    return [ "—" ] unless location

    [ location.name, location.description.to_s.strip.presence ].compact
  end

  def discount_label(percent)
    value = percent.to_f
    return "Remise" unless value.positive?

    formatted = (value % 1).zero? ? value.to_i.to_s : format("%.1f", value).tr(".", ",")
    "Remise #{formatted} %"
  end

  # Échappe le texte injecté dans le markup `inline_format` de Prawn.
  def escape(value)
    value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
  end

  def euros(cents)
    formatted = format("%.2f", cents / 100.0).tr(".", ",")
    "#{formatted} €"
  end
end
