# Compose le contenu de la note « Pizza party » posée sur le calendrier de
# claudy pour une réservation de party PRIVÉE (#259).
#
# Logique pure, sans HTTP : c'est ici que vivent toutes les règles de libellé
# (créneau en français courant, accord au pluriel, nom du groupe), et c'est ce
# qui les rend testables finement. L'envoi appartient à ClaudyClient, le
# déclenchement à SyncClaudyPartyNoteJob.
#
# claudy ne sait rien des pizza parties : la composition entière appartient à
# ce dépôt-ci (cf. les4sources/claudy#217).
class ClaudyPartyNote
  # Type de note côté claudy — le champ `color` d'une Note y tient lieu de type,
  # et « orange » est le type « Pizza party ».
  COLOR = "orange"

  # Préfixe de la clé stable envoyée à claudy : le POST y est un upsert sur
  # `external_ref`, rejouer le même appel ne duplique donc rien.
  EXTERNAL_REF_PREFIX = "tranchesdevie-order"

  TITLE = "Pizza Party privée"

  # Libellés de créneau propres à la note. Volontairement distincts de
  # PartyEvent::SLOT_LABELS (« Soir » / « Midi ») : un post-it se lit en français
  # courant, « Soirée : … » plutôt que « Soir : … ».
  SLOT_LABELS = { "soir" => "Soirée", "midi" => "Midi" }.freeze

  def self.external_ref_for(order)
    "#{EXTERNAL_REF_PREFIX}-#{order.id}"
  end

  def initialize(order)
    @order = order
  end

  # Charge utile attendue par POST /api/v1/notes côté claudy.
  def to_payload
    {
      date: date,
      color: COLOR,
      external_ref: external_ref,
      body: body
    }
  end

  def date
    @order.party_event&.held_on
  end

  def external_ref
    self.class.external_ref_for(@order)
  end

  # Deux lignes : le type de soirée, puis qui vient et combien.
  #
  #   Pizza Party privée
  #   Soirée : Michael Hulet - 18 personnes
  def body
    "#{TITLE}\n#{slot_label} : #{name} - #{people_label}"
  end

  private

  # Une party privée est toujours en soirée aujourd'hui (PartyEvent::PRIVATE_SLOT),
  # mais on ne le suppose pas : le créneau est lu sur l'événement.
  def slot_label
    SLOT_LABELS.fetch(@order.party_event&.slot.to_s, "Soirée")
  end

  def name
    @order.group_name.presence || @order.customer&.full_name
  end

  # Une boule = une personne (party_paton_count exclut déjà la ligne « forfait »).
  def people_label
    count = @order.party_paton_count
    "#{count} #{count > 1 ? 'personnes' : 'personne'}"
  end
end
