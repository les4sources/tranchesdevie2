# Envoi des e-mails du parcours Pizza party, avec leur garde d'idempotence
# (#pizza-parties).
#
# Sœur d'OrderNotificationService, mais la garde ne peut pas être la même : les
# e-mails qui PRÉCÈDENT la validation n'ont pas de commande — la garde porte donc
# sur `party_request_id`. Un lien e-mail rejoué, un job qui repasse, un
# double-clic : le client ne reçoit jamais deux fois le même e-mail.
class PartyRequestNotifier
  class << self
    def request_received(party_request)
      deliver_once(party_request, :party_request_received) do
        PartyRequestMailer.received(party_request).deliver_later
      end

      deliver_once(party_request, :party_request_team) do
        PartyRequestMailer.new_request(party_request).deliver_later
      end
    end

    def request_accepted(party_request)
      deliver_once(party_request, :party_request_accepted) do
        PartyRequestMailer.accepted(party_request).deliver_later
      end

      # Une validation tardive vaut sollicitation : l'e-mail d'acceptation porte
      # déjà la demande de confirmation et de paiement, on ne doublonne pas.
      prompt_at = party_request.payment_prompt_at
      return if prompt_at.nil? || Time.current < prompt_at

      party_request.order&.update_columns(payment_prompted_at: Time.current)
    end

    def request_refused(party_request)
      deliver_once(party_request, :party_request_refused) do
        PartyRequestMailer.refused(party_request).deliver_later
      end
    end

    def request_retracted(party_request)
      PartyRequestMailer.retracted(party_request).deliver_later
    end

    def request_expired(party_request)
      deliver_once(party_request, :party_request_expired) do
        PartyRequestMailer.request_expired(party_request).deliver_later
      end
    end

    def payment_prompt(order)
      return false if order.payment_prompted_at.present?

      PartyRequestMailer.payment_prompt(order).deliver_later
      order.update_columns(payment_prompted_at: Time.current)
      true
    end

    def payment_reminder(order)
      return false if order.payment_reminded_at.present?

      PartyRequestMailer.payment_reminder(order).deliver_later
      order.update_columns(payment_reminded_at: Time.current)
      true
    end

    def payment_expired(order)
      deliver_once_for_order(order, :party_payment_expired) do
        PartyRequestMailer.payment_expired(order).deliver_later
      end
    end

    def cancelled_by_bakery(order, reason)
      PartyRequestMailer.cancelled_by_bakery(order, reason).deliver_later
    end

    def cancelled_by_bakery(order, reason)
      PartyRequestMailer.cancelled_by_bakery(order, reason).deliver_later
      OrderNotificationService.notify_team_of_party_cancellation(order)
      true
    end

    def refunded(order)
      deliver_once_for_order(order, :party_refunded) do
        PartyRequestMailer.refunded(order).deliver_later
      end
    end

    private

    def deliver_once(party_request, kind)
      return false if EmailMessage.exists?(party_request_id: party_request.id, kind: EmailMessage.kinds[kind])

      yield
      true
    end

    def deliver_once_for_order(order, kind)
      return false if EmailMessage.exists?(order_id: order.id, kind: EmailMessage.kinds[kind])

      yield
      true
    end
  end
end
