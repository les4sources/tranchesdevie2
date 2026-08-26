# frozen_string_literal: true

# Participant NOMINATIF d'une pizza party (#206).
#
# Sert à savoir qui est venu et à pouvoir recontacter, rien d'autre. La
# comptabilité des événements concernés vient de l'agrégat `historical_*` de
# `PartyEvent` : cette table n'entre dans AUCUN calcul de revenu, et l'import
# qui la remplit ne crée aucune commande. C'est ce qui évite le double emploi.
class PartyParticipant < ApplicationRecord
  belongs_to :party_event

  # Les seules natures de place qui comptent comme participant. Les libellés
  # d'origine (« Garnitures viande », etc.) ne sont pas des places : l'import
  # les écarte et n'en crée jamais de participant.
  KINDS = %w[adult child].freeze

  validates :ticket_kind, presence: true, inclusion: { in: KINDS }
  validate :name_or_email_present

  scope :adults, -> { where(ticket_kind: "adult") }
  scope :children, -> { where(ticket_kind: "child") }
  scope :ordered, -> { order(:last_name, :first_name, :id) }

  def full_name
    [ first_name, last_name ].compact_blank.join(" ").presence || email.presence || "Sans nom"
  end

  def adult?
    ticket_kind == "adult"
  end

  def kind_label
    adult? ? "Adulte" : "Enfant"
  end

  def price_euros
    return nil if price_cents.nil?

    (price_cents / 100.0).round(2)
  end

  private

  # Une ligne de billetterie peut manquer de nom OU d'email, mais pas des deux :
  # sans l'un ni l'autre, le participant ne servirait à rien.
  def name_or_email_present
    return if first_name.present? || last_name.present? || email.present?

    errors.add(:base, "Un participant doit avoir au moins un nom ou un e-mail")
  end
end
