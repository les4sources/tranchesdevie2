# frozen_string_literal: true

require "csv"

# Import de la liste NOMINATIVE des participants d'une party, depuis un export
# de billetterie externe (#206).
#
# Ce que l'import ne fait PAS, et c'est le point : il ne crée aucune `Order`, ne
# touche pas aux colonnes `historical_*` de l'événement, et n'entre dans aucun
# calcul de revenu. La comptabilité de ces événements est déjà faite en agrégé —
# créer des commandes pour ces participants ferait double emploi.
#
# Le fichier réel contient des données personnelles : il n'est JAMAIS versionné.
# L'import prend donc un chemin en argument, fourni au moment de l'exécution.
#
# Format attendu (export BilletWeb) : séparateur « ; », valeurs entre
# guillemets, BOM UTF-8, colonnes `Tarif`, `Nom`, `Prénom`, `Email`,
# `Commande`, `Prix`, `Payé`.
class PartyParticipantImporter
  Result = Struct.new(:created, :skipped_non_place, :already_present, :adults, :children,
                      keyword_init: true) do
    def summary
      [
        "#{created} participant#{'s' if created > 1} créé#{'s' if created > 1}",
        "#{adults} adulte#{'s' if adults > 1}",
        "#{children} enfant#{'s' if children > 1}",
        "#{already_present} déjà présent#{'s' if already_present > 1}",
        "#{skipped_non_place} ligne#{'s' if skipped_non_place > 1} ignorée#{'s' if skipped_non_place > 1} (pas une place)"
      ].join(" · ")
    end
  end

  SEPARATOR = ";"

  # Un « Tarif » est une place s'il mentionne adulte ou enfant. Tout le reste —
  # « Garnitures viande », « Garnitures végé » — n'est pas une place : décision
  # du 20/07/2026, ces lignes sont gérées côté 4 Sources.
  ADULT_PATTERN = /adulte/i
  CHILD_PATTERN = /enfant/i

  attr_reader :errors

  def initialize(party_event:, path:)
    @party_event = party_event
    @path = path
    @errors = []
  end

  def call
    return failure("Événement introuvable") if @party_event.nil?
    return failure("Fichier introuvable : #{@path}") unless File.exist?(@path.to_s)

    result = Result.new(created: 0, skipped_non_place: 0, already_present: 0, adults: 0, children: 0)

    rows.each do |row|
      kind = ticket_kind(row["Tarif"])

      if kind.nil?
        result.skipped_non_place += 1
        next
      end

      attributes = attributes_for(row, kind)

      # Idempotence : la clé (événement, commande, nom, prénom, nature) est
      # unique en base ; on cherche d'abord, on crée ensuite.
      existing = PartyParticipant.find_by(attributes.slice(:party_event_id, :external_reference,
                                                           :last_name, :first_name, :ticket_kind))
      if existing
        result.already_present += 1
        next
      end

      participant = PartyParticipant.new(attributes)
      unless participant.save
        @errors << "Ligne ignorée (#{participant.errors.full_messages.to_sentence})"
        next
      end

      result.created += 1
      kind == "adult" ? result.adults += 1 : result.children += 1
    end

    result
  end

  private

  def failure(message)
    @errors << message
    nil
  end

  # `bom|utf-8` retire le BOM que produit l'export ; sans lui, la première
  # colonne s'appellerait « ﻿Tarif » et ne serait jamais trouvée.
  def rows
    CSV.read(@path, headers: true, col_sep: SEPARATOR, encoding: "bom|utf-8")
  end

  def ticket_kind(label)
    return nil if label.blank?
    return "adult" if label.match?(ADULT_PATTERN)
    return "child" if label.match?(CHILD_PATTERN)

    nil
  end

  def attributes_for(row, kind)
    {
      party_event_id: @party_event.id,
      first_name: row["Prénom"].to_s.strip.presence,
      last_name: row["Nom"].to_s.strip.presence,
      email: row["Email"].to_s.strip.downcase.presence,
      ticket_kind: kind,
      external_reference: row["Commande"].to_s.strip.presence,
      external_ticket_label: row["Tarif"].to_s.strip.presence,
      price_cents: parse_price(row["Prix"]),
      external_paid: parse_paid(row["Payé"])
    }
  end

  def parse_price(value)
    return nil if value.blank?

    (value.to_s.tr(",", ".").to_f * 100).round
  end

  def parse_paid(value)
    value.to_s.strip.downcase.in?(%w[oui yes true 1 payé paye])
  end
end
