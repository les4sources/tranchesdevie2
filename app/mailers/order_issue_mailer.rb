# Signalement d'un problème de retrait, adressé à l'ÉQUIPE (#remboursement-partiel).
#
# Notification interne, comme PartyMailer : pas de `X-Customer-Id` (le
# destinataire n'est pas le client), pas de lien de désinscription, et l'opt-out
# du client n'a aucune prise dessus. L'intercepteur `BakeryBccInterceptor` met
# Michael en copie parce que l'adresse surveillée est celle-ci.
class OrderIssueMailer < ApplicationMailer
  def reported(order_issue)
    @order_issue = order_issue
    @order = order_issue.order
    @customer = order_issue.customer
    @issue_items = order_issue.order_issue_items.includes(order_item: { product_variant: :product })
    @admin_order_url = admin_order_url(@order)

    headers["X-Email-Kind"] = "order_issue_reported"
    headers["X-Order-Id"] = @order.id

    mail(to: self.class.notification_to, subject: subject_for(@order, @customer))
  end

  # L'adresse de l'équipe boulangère — la même que celle surveillée par
  # l'intercepteur de copie cachée, pour qu'il n'y ait qu'un réglage à changer.
  def self.notification_to
    ENV.fetch("BAKERY_NOTIFICATION_ADDRESS", "boulangerie@les4sources.be")
  end

  private

  def subject_for(order, customer)
    date = order.event_date ? I18n.l(order.event_date, format: "%-d %B") : "date inconnue"
    "Problème signalé — commande #{order.order_number} (#{customer.full_name}, #{date})"
  end
end
