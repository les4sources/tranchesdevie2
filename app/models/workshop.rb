# frozen_string_literal: true

# Atelier (#208) : atelier pain, atelier pizza… « Ça, c'est encore des revenus
# complémentaires », au moins trois sur septembre, et jusqu'ici invisibles de
# l'application.
#
# Un atelier porte une date, un intitulé, un descriptif, des notes et une
# recette. Ses animateurs sont des `Artisan` — le MÊME mécanisme que les jours
# de production, pour que les partenariats (Romane / Stéphanie 50/50, y compris
# quand l'une est absente) s'appliquent sans qu'on ait à les réimplémenter.
class Workshop < ApplicationRecord
  has_many :workshop_artisans, dependent: :destroy
  has_many :artisans, through: :workshop_artisans

  validates :held_on, presence: true
  validates :title, presence: true
  validates :revenue_cents, presence: true,
                            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(held_on: :desc, id: :desc) }
  scope :between, ->(start_date, end_date) { where(held_on: start_date..end_date) }
  scope :upcoming, -> { where(held_on: Date.current..).order(:held_on) }

  # Un atelier sans animateur n'est pas refusé — on peut vouloir noter la date
  # d'un atelier avant de savoir qui l'animera — mais il est signalé comme non
  # réparti partout où il apparaît (#208).
  def unassigned?
    artisans.empty?
  end

  def revenue_euros
    (revenue_cents / 100.0).round(2)
  end

  def revenue_euros=(value)
    self.revenue_cents = value.to_s.strip.blank? ? 0 : (value.to_s.tr(",", ".").to_f * 100).round
  end
end
