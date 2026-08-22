# frozen_string_literal: true

# Réglage singleton des messages de notification client, éditable depuis
# l'admin (page « Notifications »). Pour l'instant il ne couvre que le message
# « commande prête », décliné en deux variantes (payée / à payer sur place) et
# servi à l'identique par SMS et par email.
#
# Le pattern (self.current + ensure_singleton) reprend ProductionSetting.
class NotificationSetting < ApplicationRecord
  extend ActionView::Helpers::NumberHelper

  # Textes par défaut = reprise exacte des anciens messages hardcodés de
  # SmsService.send_ready, avec la variable {montant} là où le montant était
  # interpolé. Modifier un défaut ici ne réécrit PAS un enregistrement existant.
  DEFAULT_READY_SMS_BODY =
    "Bonjour, ta commande de pains est prête, elle est disponible dans " \
    "l'épicerie aux 4 Sources (Fonds d'Ahinvaux 1, Yvoir) ! " \
    "Les artisans de Tranche de Vie"

  DEFAULT_READY_SMS_BODY_UNPAID =
    "Bonjour, ta commande de pains est prête, elle est disponible dans " \
    "l'épicerie aux 4 Sources (Fonds d'Ahinvaux 1, Yvoir) ! " \
    "Si tu paies sur place (total de ta commande: {montant}), merci de le " \
    "noter dans le carnet près du rack. Les artisans de Tranche de Vie"

  DEFAULT_READY_EMAIL_SUBJECT = "Ta commande de pains est prête"

  # Variables interpolables dans les corps de message (documentées dans l'UI).
  AVAILABLE_VARIABLES = %w[prenom nom montant numero].freeze

  def self.current
    first || create!(
      ready_sms_body: DEFAULT_READY_SMS_BODY,
      ready_sms_body_unpaid: DEFAULT_READY_SMS_BODY_UNPAID,
      ready_email_subject: DEFAULT_READY_EMAIL_SUBJECT
    )
  end

  # Corps du message « prête » pour une commande donnée : choisit la variante
  # (payée / non-payée) puis interpole les variables. Sert de corps au SMS ET
  # à l'email — une seule source de vérité par variante.
  def rendered_ready_message(order)
    template = order.unpaid_ready? ? ready_sms_body_unpaid : ready_sms_body
    interpolate(template.to_s, order)
  end

  # Sujet de l'email « prête ». Interpolé lui aussi pour autoriser {prenom} etc.
  def rendered_ready_email_subject(order)
    interpolate(ready_email_subject.presence || DEFAULT_READY_EMAIL_SUBJECT, order)
  end

  private

  def interpolate(text, order)
    customer = order.customer
    values = {
      "prenom" => customer&.first_name.to_s,
      "nom" => customer&.last_name.to_s,
      "montant" => format_amount(order),
      "numero" => order.order_number.to_s
    }
    # Remplace {cle} par sa valeur ; toute variable inconnue devient vide plutôt
    # que de lever une exception au moment de l'envoi.
    text.gsub(/\{(\w+)\}/) { values.fetch(Regexp.last_match(1), "") }
  end

  def format_amount(order)
    self.class.number_to_currency(
      order.total_euros,
      unit: "€", separator: ",", delimiter: ""
    ).gsub(",00", "")
  end

  def ensure_singleton
    if self.class.exists?
      errors.add(:base, "Il ne peut y avoir qu'un seul paramètre de notification")
      throw(:abort)
    end
  end

  before_create :ensure_singleton
end
