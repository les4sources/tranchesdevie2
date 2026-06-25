require "prawn"
require "prawn/table"
require "rqrcode"

# Génère le PDF d'un **relevé de commandes** (order statement) avec Prawn (Ruby
# pur, aucun binaire système). Ce relevé est destiné à être **joint à la
# facture** — ce n'est PAS une facture fiscale (décision produit Michael, 25/06).
#
# Contenu : coordonnées boulangerie + client, période/commandes, détail des
# articles (nom produit + variante, quantité, prix unitaire, total ligne),
# total. Pas de bloc TVA / HT-TTC, pas de mention « Facture ».
#
# S'y ajoutent :
#   - une invitation à consulter le détail des commandes en ligne ;
#   - un QR code menant à l'espace client (liste des commandes) ;
#   - un rappel que la connexion reste nécessaire, avec l'identifiant à utiliser
#     (téléphone et/ou e-mail du client).
#
# Pour un relevé de **période** (mensuel groupé, clients pro), les commandes
# sont regroupées **par jour de cuisson**, chaque jour identifiable (cf. #27).
#
# Usage :
#   pdf = InvoicePdfService.new(invoice).render   # => String binaire (PDF)
class InvoicePdfService
  BRAND_COLOR = "7C2D12".freeze   # terracotta (cf. e-mails)
  MUTED_COLOR = "8A8178".freeze
  LIGHT_FILL = "FAF7F2".freeze

  DOCUMENT_TITLE = "Relevé de commandes".freeze
  ONLINE_DETAILS_MENTION = "Tous les détails de vos commandes sont disponibles en ligne.".freeze
  QR_SIZE = 96 # côté du QR en points PDF

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
    "releve-commandes-#{@invoice.number}.pdf"
  end

  private

  def document
    pdf = Prawn::Document.new(page_size: "A4", margin: 40)
    pdf.font_families.update(default: pdf.font_families["Helvetica"])

    render_header(pdf)
    render_parties(pdf)
    render_meta(pdf)
    render_body(pdf)
    render_total(pdf)
    render_online_access(pdf)
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
    pdf.text DOCUMENT_TITLE, size: 16, style: :bold
    pdf.move_down 12
  end

  def render_parties(pdf)
    bakery = BakeryDetails.address_lines.join("\n")
    customer = @presenter.customer_address_lines.join("\n")

    pdf.table(
      [ [ box("Boulangerie", bakery), box("Client", customer) ] ],
      width: pdf.bounds.width,
      column_widths: [ pdf.bounds.width / 2, pdf.bounds.width / 2 ],
      cell_style: { borders: [], padding: [ 0, 8, 0, 0 ] }
    )
    pdf.move_down 14
  end

  def box(title, content)
    "#{title}\n#{content}"
  end

  # Référence discrète (date / période) — sans aucune mention « facture ».
  def render_meta(pdf)
    rows = [ [ "Date du relevé", I18n.l(@presenter.issued_on) ] ]
    rows << [ "Période", @presenter.period_label ] if @presenter.period?

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

  # Relevé de période : un sous-tableau par jour de cuisson, identifiable.
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

  # Un seul total (montant des commandes) — aucun découpage HT / TVA / TTC.
  def render_total(pdf)
    pdf.move_down 6
    pdf.table(
      [ [ "Total", euros(@presenter.total_cents) ] ],
      position: :right,
      column_widths: [ 120, 90 ],
      cell_style: { size: 12, padding: [ 4, 6 ], borders: [], font_style: :bold }
    ) do |t|
      t.columns(0..1).align = :right
    end
  end

  # Bloc « accès en ligne » : mention, QR code vers l'espace client, et rappel
  # de l'identifiant de connexion (téléphone et/ou e-mail).
  def render_online_access(pdf)
    pdf.move_down 24
    pdf.stroke_color "EEEEEE"
    pdf.stroke_horizontal_rule
    pdf.stroke_color "000000"
    pdf.move_down 14

    qr_png = qr_code_png(customer_space_url)
    qr_box_width = QR_SIZE + 16

    pdf.float do
      pdf.image StringIO.new(qr_png), at: [ pdf.bounds.right - QR_SIZE, pdf.cursor ],
        width: QR_SIZE, height: QR_SIZE
    end

    pdf.text_box(
      online_access_text,
      at: [ 0, pdf.cursor ],
      width: pdf.bounds.width - qr_box_width,
      size: 10,
      inline_format: true
    )

    pdf.move_down [ QR_SIZE, online_access_lines_height(pdf) ].max + 8
  end

  def online_access_text
    lines = [ "<b>#{ONLINE_DETAILS_MENTION}</b>" ]
    lines << "Scannez le QR code ou rendez-vous sur #{customer_space_url}."
    lines << "Une connexion reste nécessaire. Identifiant à utiliser : " \
             "#{@presenter.login_identifiers.join(' ou ')}."
    lines.join("\n\n")
  end

  # Hauteur approximative du bloc texte, pour réserver la place sous le QR.
  def online_access_lines_height(pdf)
    pdf.height_of(
      online_access_text,
      width: pdf.bounds.width - (QR_SIZE + 16),
      size: 10,
      inline_format: true
    )
  end

  def render_footer(pdf)
    pdf.move_down 12
    pdf.fill_color MUTED_COLOR
    pdf.text "Merci de votre confiance.", size: 9, align: :center
    pdf.text [ BakeryDetails::NAME, BakeryDetails::EMAIL ].join(" · "), size: 8, align: :center
    pdf.fill_color "000000"
  end

  # URL de l'espace client (liste de ses commandes). Le chemin est résolu via le
  # routeur ; l'hôte vient de APP_HOST (cohérent avec les liens des e-mails).
  # HTTPS en production (lien public scanné par le client) ; http ailleurs pour
  # rester compatible avec localhost / lvh.me en développement et test.
  def customer_space_url
    Rails.application.routes.url_helpers.customers_account_url(host: app_host, protocol: url_protocol)
  end

  def app_host
    ENV.fetch("APP_HOST", "tranchesdevie.be")
  end

  def url_protocol
    Rails.env.production? ? "https" : "http"
  end

  # PNG (binaire) du QR code encodant l'URL fournie. `size` fixe le côté en
  # pixels du PNG ; Prawn le redimensionne ensuite à QR_SIZE points.
  def qr_code_png(url)
    RQRCode::QRCode.new(url).as_png(
      size: 240,
      border_modules: 2
    ).to_s
  end

  def euros(cents)
    formatted = format("%.2f", cents / 100.0).tr(".", ",")
    "#{formatted} €"
  end
end
