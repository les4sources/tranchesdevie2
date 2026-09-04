# frozen_string_literal: true

# Point de retrait d'une commande (#148). Chaque fournée ouvre un sous-ensemble
# de lieux : « Les 4 Sources » (le lieu par défaut) est ouvert partout, tandis
# que « Marché d'Anhée » n'existe que les jours de marché.
#
# Deux textes, deux questions distinctes (#252) : `description` répond à
# « c'est où ? » et s'affiche au moment du choix (checkout, calendrier) ;
# `pickup_instructions` répond à « quand est-ce que je viens ? » et s'affiche
# une fois la commande passée (confirmation, e-mail, page commande). Les
# horaires dépendent du lieu — 18h aux 4 Sources, les heures du marché à
# Anhée — donc c'est un texte libre saisi par les boulangers, jamais calculé.
#
# Suppression = soft delete (comme MoldType) : un lieu retiré disparaît des
# sélecteurs client mais reste lisible sur les commandes passées qui le
# référencent. Aucun `default_scope` n'est posé, c'est ce qui rend cette lecture
# possible — filtrer explicitement avec `not_deleted` dans les sélecteurs.
class PickupLocation < ApplicationRecord
  has_soft_deletion

  has_many :bake_day_pickup_locations, dependent: :destroy
  has_many :bake_days, through: :bake_day_pickup_locations
  has_many :orders, dependent: :restrict_with_error
  # Produits exclus de ce lieu de retrait (#152) : non commandables ici.
  has_many :product_pickup_location_exclusions, dependent: :destroy
  has_many :excluded_products, through: :product_pickup_location_exclusions, source: :product

  validates :name, presence: true, uniqueness: { conditions: -> { where(deleted_at: nil) } }
  validate :single_default_location
  validate :default_location_stays_active
  validate :bake_days_in_use_still_open

  after_save :sync_bake_days

  scope :not_deleted, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(position: :asc, name: :asc) }
  # Lieux encore proposables au client (#199). `active` est un drapeau
  # d'exploitation, pas une suppression : un lieu inactif garde ses commandes,
  # sa feuille de retrait et sa place dans la répartition du jour.
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  # Le lieu par défaut (« Les 4 Sources ») : pré-sélectionné au checkout, ouvert
  # automatiquement sur chaque nouvelle fournée. Peut être nil sur une base neuve
  # (aucun lieu créé) — les appelants doivent le tolérer.
  def self.default_location
    not_deleted.find_by(default: true)
  end

  # Seules les fournées à venir sont cochables depuis la fiche d'un lieu : on ne
  # rouvre ni ne ferme un lieu sur une fournée déjà cuite.
  def self.assignable_bake_days
    BakeDay.future.ordered
  end

  # Même raison que dans BakeDay : le setter d'ActiveRecord écrirait les
  # jointures avant validation. On met en attente, on valide, puis on applique.
  def bake_day_ids=(ids)
    @staged_bake_day_ids = Array(ids).reject(&:blank?).map(&:to_i)
  end

  def bake_day_ids
    @staged_bake_day_ids || super
  end

  private

  # Un seul lieu par défaut à la fois (doublé d'un index unique partiel en base).
  def single_default_location
    return unless default? && deleted_at.nil?

    conflicting = PickupLocation.not_deleted.where(default: true)
    conflicting = conflicting.where.not(id: id) if persisted?
    return unless conflicting.exists?

    errors.add(:default, "ne peut être coché que sur un seul point de retrait")
  end

  # Le lieu par défaut est pré-sélectionné au checkout : le laisser devenir
  # inactif reviendrait à proposer d'office un lieu qu'on vient de retirer.
  # On interdit plutôt que de transférer le défaut dans le dos de l'admin.
  def default_location_stays_active
    return unless default? && !active?

    errors.add(:active, "ne peut pas être décoché sur le point de retrait par défaut — désignez d'abord un autre lieu par défaut")
  end

  def assignable_bake_day_ids
    self.class.assignable_bake_days.pluck(:id)
  end

  def persisted_bake_day_ids
    return [] if new_record?

    BakeDayPickupLocation.where(pickup_location_id: id).pluck(:bake_day_id)
  end

  # Symétrique de la garde de BakeDay : on ne ferme pas ce lieu sur une fournée
  # dont des commandes l'utilisent déjà.
  def bake_days_in_use_still_open
    return if @staged_bake_day_ids.nil? || new_record?

    removed_ids = (persisted_bake_day_ids & assignable_bake_day_ids) - @staged_bake_day_ids

    BakeDay.where(id: removed_ids).ordered.each do |bake_day|
      count = Order.where(bake_day_id: bake_day.id, pickup_location_id: id).count
      next if count.zero?

      errors.add(
        :bake_days,
        "la fournée du #{I18n.l(bake_day.baked_on)} ne peut pas être retirée : " \
        "#{count} commande(s) y sont rattachée(s) à ce point de retrait."
      )
    end
  end

  # Réconcilie les jointures UNIQUEMENT dans le périmètre cochable (fournées à
  # venir). Les fournées passées ne figurent pas dans le formulaire : leur
  # rattachement doit survivre à un enregistrement, sans quoi l'historique des
  # commandes perdrait son lieu de retrait.
  def sync_bake_days
    staged = @staged_bake_day_ids
    @staged_bake_day_ids = nil
    return if staged.nil?

    assignable = assignable_bake_day_ids

    BakeDayPickupLocation
      .where(pickup_location_id: id, bake_day_id: assignable - staged)
      .destroy_all

    already_open = BakeDayPickupLocation.where(pickup_location_id: id).pluck(:bake_day_id)
    ((staged & assignable) - already_open).each do |bake_day_id|
      BakeDayPickupLocation.create!(pickup_location_id: id, bake_day_id: bake_day_id)
    end

    association(:bake_day_pickup_locations).reset
    association(:bake_days).reset
  end
end
