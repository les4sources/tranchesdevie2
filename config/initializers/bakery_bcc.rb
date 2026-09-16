# Copie cachée de Michael sur tout ce qui part à la boulangerie.
#
# Les e-mails adressés à `boulangerie@les4sources.be` sont les yeux de l'équipe
# sur l'application : nouvelle demande de Pizza party, réservation annulée,
# récapitulatif d'un groupe. Michael doit les voir passer sans dépendre de ce
# que quelqu'un pense à lui transférer.
#
# C'est un INTERCEPTEUR et non un `bcc:` posé dans chaque mailer : il attrape
# tout ce qui part vers cette adresse, y compris les e-mails que personne n'a
# encore écrits. Un `bcc:` par mailer serait oublié au premier ajout.
#
# La classe est définie ici plutôt que dans `app/` : un initializer qui
# référence une constante autochargée casse le rechargement de code.
class BakeryBccInterceptor
  # Adresse surveillée — celle de l'équipe, pas l'expéditeur.
  def self.watched_address
    ENV.fetch("BAKERY_NOTIFICATION_ADDRESS", "boulangerie@les4sources.be").downcase
  end

  # Destinataire de la copie. Vide (ou absent) = aucune copie, ce qui est l'état
  # normal du poste de développement et de la CI.
  def self.bcc_address
    ENV.fetch("BAKERY_BCC", "michael+tranchesdevie@hulet.eu").presence
  end

  def self.delivering_email(message)
    return if bcc_address.blank?

    recipients = (Array(message.to) + Array(message.cc)).compact.map(&:downcase)
    return unless recipients.include?(watched_address)

    existing = Array(message.bcc).compact.map(&:downcase)
    return if existing.include?(bcc_address.downcase)

    message.bcc = existing + [ bcc_address ]
  end
end

ActionMailer::Base.register_interceptor(BakeryBccInterceptor)
