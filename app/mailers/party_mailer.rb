# Notifications INTERNES liées aux Pizza parties (#168).
#
# Contrairement à OrderMailer, le destinataire n'est pas le client mais les
# équipes : pas de `X-Customer-Id`, pas de lien de désinscription, et l'opt-out
# e-mail du client n'a aucune prise dessus.
class PartyMailer < ApplicationMailer
  DEFAULT_TO = "boulangerie@les4sources.be"
  DEFAULT_CC = "sejours@les4sources.be"
  DEFAULT_ACCOUNTING_TO = "compta@les4sources.be"

  # Libellés FR des moyens d'encaissement (Order#payment_method).
  PAYMENT_METHOD_LABELS = {
    stripe: "Stripe (carte / Bancontact)",
    wallet: "Portefeuille",
    cash: "Espèces",
    transfer: "Virement"
  }.freeze

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

  # Prévient la COMPTA qu'une Pizza party privée vient d'être ENCAISSÉE (#289).
  #
  # Distinct de `new_private_party`, qui sert la production et part dès la
  # réservation : ici c'est l'argent reçu qui déclenche, parce qu'une party
  # privée s'ajoute souvent sur la facture d'un séjour de groupe. D'où le lien
  # principal vers la party (l'événement) et non vers la commande.
  def private_party_paid_for_accounting(order)
    @order = order
    @customer = order.customer
    @party_event = order.party_event
    @party_request = order.party_request
    @paton_count = order.party_paton_count
    @payment_method_label = self.class.payment_method_label(order)
    @admin_party_event_url = admin_party_event_url(@party_event)
    @admin_order_url = admin_order_url(@order)

    headers["X-Email-Kind"] = "party_accounting_notification"
    headers["X-Order-Id"] = @order.id

    mail(to: self.class.accounting_to, subject: accounting_subject_for(@order))
  end

  def self.notification_to
    ENV.fetch("PARTY_NOTIFICATION_TO", DEFAULT_TO)
  end

  def self.notification_cc
    ENV.fetch("PARTY_NOTIFICATION_CC", DEFAULT_CC)
  end

  def self.accounting_to
    ENV.fetch("PARTY_ACCOUNTING_TO", DEFAULT_ACCOUNTING_TO)
  end

  # « — » plutôt que rien : la compta doit voir qu'aucun moyen n'est tracé, pas
  # une case vide qu'elle prendrait pour un oubli de mise en page.
  def self.payment_method_label(order)
    PAYMENT_METHOD_LABELS.fetch(order.payment_method, "—")
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

  # « Pizza Party privée payée — vendredi 4 septembre, soir, 11 personnes — 110,00 € ».
  # La compta trie par montant autant que par date : les deux sont dans l'objet.
  def accounting_subject_for(order)
    event = order.party_event
    date = I18n.l(event.held_on, format: "%A %-d %B")
    people = order.party_paton_count
    amount = ActiveSupport::NumberHelper.number_to_currency(
      order.total_euros, unit: "€", separator: ",", delimiter: "", format: "%n %u", precision: 2
    )

    "Pizza Party privée payée — #{date}, #{event.slot_label.downcase}, " \
      "#{people} personne#{'s' if people > 1} — #{amount}"
  end
end
