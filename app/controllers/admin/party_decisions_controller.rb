module Admin
  # Page de décision ouverte depuis un lien d'e-mail (#pizza-parties).
  #
  # ELLE N'AGIT JAMAIS SUR UN GET. Gmail, Outlook et les scanners de sécurité
  # préchargent les liens qu'ils reçoivent : un lien « valider » qui déciderait
  # au chargement validerait des parties tout seul, sans qu'aucun boulanger ait
  # cliqué. Le GET affiche donc la demande et un bouton ; la décision part en
  # POST vers `Admin::PartyRequestsController`.
  #
  # Double barrière : le jeton signé (imprévisible, à usage dédié, expirant) ET
  # le mot de passe admin hérité de `Admin::BaseController` — un e-mail transféré
  # ne suffit pas à décider à la place de la boulangerie.
  class PartyDecisionsController < Admin::BaseController
    def show
      @party_request = PartyRequest.find_signed(params[:token], purpose: :party_decision)

      if @party_request.nil?
        render :invalid, status: :not_found
        return
      end

      @decision = params[:decision] == "refuse" ? "refuse" : "accept"
      @order = @party_request.order
    end
  end
end
