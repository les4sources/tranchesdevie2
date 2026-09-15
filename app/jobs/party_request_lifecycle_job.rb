# Cycle de vie des DEMANDES de Pizza party en attente de réponse (#pizza-parties).
#
# Deux gestes, tous deux calés sur le cut-off de la fournée qui pétrirait les
# pâtons : relancer la boulangerie qui n'a pas répondu, et clôturer une demande
# que plus personne ne peut honorer.
#
# Passage toutes les 10 minutes : les échéances sont portées par chaque fournée
# et ne tombent pas à heure fixe. Un passage quotidien honorerait une échéance
# jusqu'à 24 h trop tard.
class PartyRequestLifecycleJob < ApplicationJob
  queue_as :default

  # Silence de la boulangerie au-delà duquel on la relance, une seule fois.
  INTERNAL_REMINDER_AFTER = 48.hours

  def perform
    remind_bakery
    close_untreated
  end

  private

  # Une demande sans réponse depuis 48 h : exactement une relance interne.
  # `reminded_at` EST la garde — pas de compteur, pas de fenêtre à calculer.
  def remind_bakery
    PartyRequest.state_pending
                .where(reminded_at: nil)
                .where(created_at: ...INTERNAL_REMINDER_AFTER.ago)
                .find_each do |request|
      next unless still_honourable?(request)

      PartyRequestMailer.new_request(request).deliver_later
      request.update_columns(reminded_at: Time.current)
      Rails.logger.info("PartyRequestLifecycle: relance interne pour la demande #{request.id}")
    end
  end

  # Passé le cut-off, plus personne ne peut pétrir pour ce groupe : la demande
  # est close et le client prévenu, plutôt que de rester en attente pour rien.
  def close_untreated
    PartyRequest.state_pending.find_each do |request|
      deadline = request.deadline_at
      next if deadline.nil? || Time.current < deadline

      request.update!(state: :expired)
      PartyRequestNotifier.request_expired(request)
      Rails.logger.info("PartyRequestLifecycle: demande #{request.id} close (cut-off dépassé)")
    end
  end

  def still_honourable?(request)
    deadline = request.deadline_at
    deadline.nil? || Time.current < deadline
  end
end
