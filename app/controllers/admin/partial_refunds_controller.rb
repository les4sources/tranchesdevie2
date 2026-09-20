# Remboursement ligne à ligne depuis la fiche d'une commande (#remboursement-partiel).
class Admin::PartialRefundsController < Admin::BaseController
  def create
    order = Order.find(params[:id])

    service = PartialRefundService.new(
      order,
      lines: refund_items,
      channel: params[:channel],
      amount_cents: parse_euro_amount(params[:amount_euros]),
      reason: params[:reason],
      order_issue: order.order_issues.find_by(id: params[:order_issue_id])
    )

    if service.call
      redirect_to admin_order_path(order),
                  notice: "Remboursement de #{format('%.2f', service.partial_refund.amount_euros).tr('.', ',')} € enregistré"
    else
      redirect_to admin_order_path(order), alert: "Remboursement impossible : #{service.errors.join(' · ')}"
    end
  end

  private

  # Quantités saisies, sous la forme { "<order_item_id>" => "<qty>" }. Les clés
  # sont des identifiants de lignes, donc variables : on lit clé à clé plutôt
  # que d'ouvrir un `permit!` sur des paramètres entiers. Le service revalide
  # ensuite chaque ligne contre la commande.
  def refund_items
    raw = params[:refund_items]
    return {} if raw.blank?

    raw.keys.each_with_object({}) { |key, hash| hash[key.to_i] = raw[key].to_i }
  end

  # `nil` quand le champ est vide : le service retombe alors sur le net des
  # lignes cochées. Un montant illisible vaut « vide » plutôt qu'un zéro qui
  # passerait pour une intention.
  def parse_euro_amount(amount)
    return nil if amount.blank?

    (BigDecimal(amount.to_s.tr(",", ".")) * 100).round
  rescue ArgumentError
    nil
  end
end
