# Pose ou retire la note « Pizza party » sur le calendrier de claudy (#259).
#
# En tâche de fond, jamais dans le cycle requête : claudy indisponible ou un
# incident réseau ne doit faire échouer ni un paiement, ni un checkout, ni un
# remboursement.
class SyncClaudyPartyNoteJob < ApplicationJob
  queue_as :default

  CREATE = "create"
  DELETE = "delete"

  discard_on ActiveJob::DeserializationError
  retry_on ClaudyClient::Error, wait: :polynomially_longer, attempts: 5

  def perform(order_id, action)
    order = Order.find_by(id: order_id)
    return unless order
    # Seule une party PRIVÉE remonte : les publiques sont organisées par la
    # boulangerie et déjà connues de l'équipe.
    return unless order.private_party?

    case action.to_s
    when CREATE then create_note(order)
    when DELETE then delete_note(order)
    else Rails.logger.warn("SyncClaudyPartyNoteJob: action inconnue #{action.inspect}")
    end
  rescue ClaudyClient::Error => e
    Rails.logger.error("SyncClaudyPartyNoteJob (#{action}) — commande #{order&.order_number || order_id} : #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    raise
  end

  private

  # Garde locale en plus de l'upsert côté claudy : une commande qui porte déjà
  # une note n'en repose pas une seconde.
  def create_note(order)
    return if order.claudy_note_id.present?

    note_id = ClaudyClient.create_note(ClaudyPartyNote.new(order).to_payload)
    # nil = client non configuré (no-op) : rien à mémoriser.
    order.update_column(:claudy_note_id, note_id) if note_id.present?
  end

  def delete_note(order)
    note_id = order.claudy_note_id
    return if note_id.blank?

    ClaudyClient.delete_note(note_id)
    order.update_column(:claudy_note_id, nil)
  end
end
