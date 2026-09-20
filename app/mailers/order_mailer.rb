class OrderMailer < ApplicationMailer
  # Order confirmation email, sent once an order is paid (non-OTP → carries an
  # unsubscribe link in the footer).
  def confirmation(order)
    @order = order
    @customer = order.customer
    @items = order.order_items.includes(product_variant: :product)
    # Où et quand venir (#252). Toujours présent : `pickup_location_id` est
    # NOT NULL et l'association est requise — d'où l'absence de garde côté vue.
    @pickup_location = order.pickup_location
    @order_url = order_url(@order.public_token)
    @unsubscribe_url = email_preferences_url(token: @customer.signed_id(purpose: :email_unsubscribe))

    headers["X-Customer-Id"] = @customer.id
    headers["X-Email-Kind"] = "confirmation"
    headers["X-Order-Id"] = @order.id

    mail(to: @customer.email, subject: "Confirmation de ta commande #{@order.order_number}")
  end

  # Remboursement partiel (#remboursement-partiel) : la trace écrite de ce que
  # les boulangers ont rendu, ligne à ligne. Transactionnel dans l'esprit, mais
  # il reste soumis à l'opt-out comme tout ce qui n'est pas un code de connexion
  # — le SMS prend le relais sinon.
  def partial_refund(partial_refund)
    @partial_refund = partial_refund
    @order = partial_refund.order
    @customer = @order.customer
    @items = partial_refund.partial_refund_items.includes(order_item: { product_variant: :product })
    @order_url = order_url(@order.public_token)
    @unsubscribe_url = email_preferences_url(token: @customer.signed_id(purpose: :email_unsubscribe))

    headers["X-Customer-Id"] = @customer.id
    headers["X-Email-Kind"] = "partial_refund"
    headers["X-Order-Id"] = @order.id

    mail(to: @customer.email, subject: "Remboursement sur ta commande #{@order.order_number}")
  end

  # « Commande prête » — envoyé quand les boulangers marquent la commande prête,
  # en même temps que le SMS. Le corps et le sujet viennent de NotificationSetting
  # (éditables depuis l'admin) ; même texte que le SMS pour la variante concernée.
  def ready(order)
    @order = order
    @customer = order.customer
    setting = NotificationSetting.current
    @body = setting.rendered_ready_message(order)
    @order_url = order_url(@order.public_token)
    @unsubscribe_url = email_preferences_url(token: @customer.signed_id(purpose: :email_unsubscribe))

    headers["X-Customer-Id"] = @customer.id
    headers["X-Email-Kind"] = "ready"
    headers["X-Order-Id"] = @order.id

    mail(to: @customer.email, subject: setting.rendered_ready_email_subject(order))
  end
end
