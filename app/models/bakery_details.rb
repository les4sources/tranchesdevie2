# Coordonnées de la boulangerie, centralisées pour la facturation (#38).
#
# Source de vérité unique des coordonnées affichées sur les factures PDF (et
# réutilisable ailleurs). Les valeurs reprennent celles déjà présentes dans les
# e-mails (layout mailer, confirmation de commande).
#
# La SPRL facture potentiellement avec TVA (décision compta en cours, cf. note
# TVA de #38) : le numéro d'entreprise et le taux de TVA par défaut sont donc
# paramétrables via variables d'environnement, sans bloquer la génération.
module BakeryDetails
  NAME = "Tranches de Vie"
  TAGLINE = "Boulangerie artisanale"
  ADDRESS_LINE = "Les 4 Sources, Fonds d'Ahinvaux 1"
  POSTAL_CITY = "5530 Yvoir"
  COUNTRY = "Belgique"
  EMAIL = ENV.fetch("MAIL_FROM", "boulangerie@les4sources.be")

  module_function

  # Numéro d'entreprise (BCE/TVA). Optionnel : affiché seulement s'il est défini.
  def company_number
    ENV["BAKERY_COMPANY_NUMBER"].presence
  end

  # Taux de TVA par défaut (en pourcentage). 0 par défaut → HT == TTC, ne bloque
  # jamais la génération de la facture (note TVA #38).
  def default_vat_rate
    BigDecimal(ENV.fetch("BAKERY_VAT_RATE", "0"))
  rescue ArgumentError
    BigDecimal("0")
  end

  # Bloc d'adresse multi-lignes, prêt à l'affichage.
  def address_lines
    [ NAME, ADDRESS_LINE, POSTAL_CITY, COUNTRY ].tap do |lines|
      lines << "N° entreprise : #{company_number}" if company_number
      lines << EMAIL
    end
  end
end
