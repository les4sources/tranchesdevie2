# Les problèmes signalés par les clients au retrait (#remboursement-partiel).
#
# Écran de tri : ce qui attend une décision d'abord, l'historique ensuite. Le
# remboursement, lui, se fait depuis la fiche de la commande.
class Admin::OrderIssuesController < Admin::BaseController
  def index
    @state = params[:state].presence_in(%w[open resolved]) || "open"
    @issues = OrderIssue.where(state: @state)
                        .includes(:customer, :partial_refunds, order: :bake_day, order_issue_items: { order_item: { product_variant: :product } })
                        .recent
    @open_count = OrderIssue.state_open.count
    @resolved_count = OrderIssue.state_resolved.count
  end

  # Clore un signalement sans rembourser : le pain a été remplacé sur place, ou
  # le boulanger a appelé le client. Un remboursement le clôt tout seul.
  def resolve
    issue = OrderIssue.find(params[:id])
    issue.resolve!(by: "admin")

    redirect_back fallback_location: admin_order_issues_path, notice: "Signalement marqué comme traité"
  end
end
