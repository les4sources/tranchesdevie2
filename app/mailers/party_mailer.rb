# Notifications INTERNES liées aux Pizza parties (#168).
#
# Contrairement à OrderMailer, le destinataire n'est pas le client mais les
# équipes : pas de `X-Customer-Id`, pas de lien de désinscription, et l'opt-out
# e-mail du client n'a aucune prise dessus.
class PartyMailer < ApplicationMailer
  DEFAULT_TO = "boulangerie@les4sources.be"
  DEFAULT_CC = "sejours@les4sources.be"

  # Prévient boulangers et équipe séjours qu'une party privée vient d'être
  # réservée. Une party privée n'apparaît sur aucune feuille de production : sans
  # cet e-mail, elle attend qu'on pense à ouvrir l'onglet Parties.
  def new_private_party(order)
    @order = order
    @customer = order.customer
    @party_event = order.party_event
    @paton_count = order.party_paton_count
    @admin_order_url = admin_order_url(@order)
    @oven_already_hot = BakeDay::COOKING_WDAYS.include?(@party_event.held_on.wday)

    headers["X-Email-Kind"] = "party_team_notification"
    headers["X-Order-Id"] = @order.id

    mail(to: self.class.notification_to, cc: self.class.notification_cc, subject: subject_for(@order))
  end

  def self.notification_to
    ENV.fetch("PARTY_NOTIFICATION_TO", DEFAULT_TO)
  end

  def self.notification_cc
    ENV.fetch("PARTY_NOTIFICATION_CC", DEFAULT_CC)
  end

  private

  # « Nouvelle Pizza Party privée — vendredi 4 septembre, soir, 11 personnes » :
  # de quoi trier sa boîte sans ouvrir l'e-mail.
  def subject_for(order)
    event = order.party_event
    # Sans l'année : l'e-mail se lit dans les semaines qui précèdent la party.
    date = I18n.l(event.held_on, format: "%A %-d %B")
    people = order.party_paton_count

    "Nouvelle Pizza Party privée — #{date}, #{event.slot_label.downcase}, " \
      "#{people} personne#{'s' if people > 1}"
  end
end
