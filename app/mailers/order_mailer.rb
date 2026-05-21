class OrderMailer < ApplicationMailer
  # Order confirmation email, sent once an order is paid (non-OTP → carries an
  # unsubscribe link in the footer).
  def confirmation(order)
    @order = order
    @customer = order.customer
    @items = order.order_items.includes(product_variant: :product)
    @order_url = order_url(@order.public_token)
    @unsubscribe_url = email_preferences_url(token: @customer.signed_id(purpose: :email_unsubscribe))

    headers["X-Customer-Id"] = @customer.id
    headers["X-Email-Kind"] = "confirmation"
    headers["X-Order-Id"] = @order.id

    mail(to: @customer.email, subject: "Confirmation de ta commande #{@order.order_number}")
  end
end
