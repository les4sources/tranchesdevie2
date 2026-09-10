# Écarts de montant : les commandes dont le total ne se déduit pas de leur
# détail (#retour Manon). Écran de relecture pour la compta, et son PDF.
#
# La détection vit dans AmountDiscrepancyService ; ce contrôleur ne fait que la
# présenter, à l'écran (avec un lien vers chaque commande, pour corriger) ou en
# PDF (pour faire le point sur papier).
class Admin::AmountDiscrepanciesController < Admin::BaseController
  def index
    @report = AmountDiscrepancyService.new.call

    respond_to do |format|
      format.html
      format.pdf do
        service = AmountDiscrepancyPdfService.new(@report)
        send_data service.render,
          filename: service.filename,
          type: "application/pdf",
          disposition: "attachment"
      end
    end
  end
end
