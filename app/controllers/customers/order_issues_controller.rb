# Signalement d'un problème sur une commande retirée (#remboursement-partiel).
#
# Le client décrit ce qui cloche et coche les lignes concernées ; l'équipe reçoit
# l'e-mail. Rien ici ne rembourse quoi que ce soit : un signalement est une
# demande, la décision appartient aux boulangers.
class Customers::OrderIssuesController < ApplicationController
  before_action :authenticate_customer!
  before_action :set_order

  def new
    @order_issue = @order.order_issues.new
  end

  def create
    @order_issue = @order.order_issues.new(
      customer: current_customer,
      description: params.dig(:order_issue, :description).to_s.strip
    )
    assign_reported_items

    if @order_issue.save
      OrderNotificationService.notify_team_of_order_issue(@order_issue)
      redirect_to customers_account_path,
                  notice: "Merci — les boulangers ont reçu ton signalement. Ils te recontactent au plus vite."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_order
    @order = current_customer.orders
                             .includes(order_items: { product_variant: :product })
                             .find_by(id: params[:id])

    return redirect_to customers_account_path, alert: "Commande introuvable" if @order.nil?

    # Fenêtre volontairement fermée au-delà de deux semaines : passé ce délai le
    # client appelle, on ne rouvre pas une fournée du mois dernier depuis un
    # formulaire.
    return if @order.can_report_issue_by_customer?

    redirect_to customers_account_path,
                alert: "Cette commande ne peut plus faire l'objet d'un signalement. Appelle-nous, on regarde ensemble."
  end

  # Quantités cochées, bornées par ce qui a réellement été commandé sur la ligne.
  def assign_reported_items
    reported = params[:reported_items] || {}

    @order.order_items.each do |item|
      qty = reported[item.id.to_s].to_i
      next unless qty.positive?

      @order_issue.order_issue_items.new(order_item: item, qty: [ qty, item.qty ].min)
    end
  end
end
