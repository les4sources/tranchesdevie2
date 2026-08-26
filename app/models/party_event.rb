class PartyEvent < ApplicationRecord
  has_soft_deletion

  # Une source vide (« — ») équivaut à pas d'import historique.
  before_validation { self.historical_source = nil if historical_source.blank? }

  # Type d'événement party (#pizza-parties).
  enum :kind, { public_party: 0, private_party: 1 }, prefix: :kind
  # Créneau : requis en privé, optionnel en public.
  enum :slot, { midi: 0, soir: 1 }, prefix: :slot

  # Commandes rattachées à l'événement (inscriptions publiques / réservation privée).
  has_many :orders, dependent: :nullify

  validates :held_on, presence: true
  validates :kind, presence: true
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :slot, presence: true, if: :kind_private_party?
  # Une party PUBLIQUE est organisée par la boulangerie : capacité et clôture des
  # inscriptions sont obligatoires ; elle n'a pas de créneau (toujours en soirée).
  # Exception : un import historique (BilletWeb) n'a pas d'inscription en ligne.
  validates :title, presence: true, if: :kind_public_party?
  validates :capacity, presence: true, if: -> { kind_public_party? && !historical? }
  validates :registration_closes_at, presence: true, if: -> { kind_public_party? && !historical? }

  scope :not_deleted, -> { where(deleted_at: nil) }
  scope :public_events, -> { kind_public_party }
  scope :private_events, -> { kind_private_party }
  scope :upcoming, -> { not_deleted.where(held_on: Date.current..).order(:held_on, :slot) }
  scope :past, -> { not_deleted.where(held_on: ...Date.current).order(held_on: :desc) }
  # Événements dont les ventes ont été importées en agrégé (ex. BilletWeb).
  scope :historical, -> { not_deleted.where.not(historical_source: nil) }

  # Ventes agrégées importées (BilletWeb) : capacité/clôture obligatoires ne
  # s'appliquent qu'aux inscriptions du site — un import historique renseigne
  # ses comptes adultes/enfants + frais à la place.
  validates :historical_adults, :historical_children, :historical_fees_cents, :historical_sourciers,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :historical_adults, :historical_children, :historical_fees_cents,
            presence: true, if: :historical?

  SLOT_LABELS = { "midi" => "Midi", "soir" => "Soir" }.freeze

  # Jours et créneau ouverts aux parties PRIVÉES (#201, réunion du 25/08/2026).
  #
  # Mardi et vendredi parce que ce sont les jours de boulangerie : le four est
  # déjà chaud, et un groupe qui le chauffe lui-même l'abîme (« on va péter le
  # four, en deux ans il sera foutu »). Le SOIR seulement, parce qu'à midi les
  # boulangers sont encore sur leur fournée — pains en train de lever,
  # températures incompatibles, et personne pour accueillir le groupe.
  #
  # Volontairement une constante littérale et non `BakeDay::COOKING_WDAYS` :
  # les deux valent [2, 5] aujourd'hui pour la même raison, mais ajouter un jour
  # de cuisson ne doit pas ouvrir des pizza parties dans le dos de l'équipe.
  PRIVATE_WDAYS = [ 2, 5 ].freeze
  PRIVATE_SLOT = "soir"

  # Réservation possible jusqu'à la VEILLE 16 h 00, heure de Bruxelles. Le
  # fuseau est explicite (et non `Time.zone`) : la règle est celle de la
  # boulangerie, pas celle du serveur, et elle doit suivre l'heure d'été.
  PRIVATE_BOOKING_ZONE = "Europe/Brussels"
  PRIVATE_BOOKING_CUT_OFF_HOUR = 16

  # Instant limite pour réserver le créneau du `date` donné.
  def self.private_booking_deadline(date)
    day = date.to_date.prev_day
    ActiveSupport::TimeZone[PRIVATE_BOOKING_ZONE].local(day.year, day.month, day.day, PRIVATE_BOOKING_CUT_OFF_HOUR, 0, 0)
  end

  # Encore dans les temps ? Strict : à 16 h 00 pile, c'est fermé.
  def self.private_booking_open?(date)
    Time.current < private_booking_deadline(date)
  end

  # Jour ET créneau ouverts à la réservation privée, indépendamment de
  # l'occupation. Séparé de `private_slot_available?` pour que le service de
  # réservation puisse distinguer « jour interdit » de « déjà complet ».
  def self.private_bookable_slot?(date, slot)
    return false if date.blank? || slot.blank?

    PRIVATE_WDAYS.include?(date.to_date.wday) && slot.to_s == PRIVATE_SLOT
  end

  # Capacité par créneau des parties PRIVÉES (réglage singleton).
  def self.private_slot_capacity
    ProductionSetting.current.private_party_slot_capacity
  end

  # Un (date, créneau) privé est-il réservable ? Ouvert par défaut ; indisponible
  # si la date est passée, si l'admin l'a bloqué, si une party PUBLIQUE (toujours en
  # soirée) occupe déjà cette date le soir, ou si la capacité (nombre de parties
  # privées déjà sur ce créneau) est atteinte.
  def self.private_slot_available?(date, slot)
    return false if date.blank? || slot.blank?
    return false unless private_bookable_slot?(date, slot)
    return false unless private_booking_open?(date)
    return false if PartySlotBlock.blocked?(date, slot)
    return false if slot.to_s == "soir" && public_party_scheduled?(date)

    private_events.not_deleted.where(held_on: date, slot: slot).count < private_slot_capacity
  end

  # Disponibilité des créneaux privés sur une plage de dates, en requêtes
  # groupées (le calendrier client interroge ~8 semaines : pas de
  # private_slot_available? par jour, qui ferait 4 requêtes × 2 créneaux × 56
  # jours). Renvoie { date => { "midi" => bool, "soir" => bool } }.
  # Même logique que private_slot_available? — qui reste la vérification
  # autoritaire à l'unité (ajout panier, checkout).
  def self.private_availability(range)
    capacity = private_slot_capacity
    # slot nil = journée entière bloquée ; on normalise en noms de créneau
    # (pluck caste l'enum en nom selon la version de Rails — on accepte les deux).
    slot_names = PartySlotBlock.slots.invert
    blocked = PartySlotBlock.where(blocked_on: range)
                            .pluck(:blocked_on, :slot)
                            .map { |date, slot| [ date, slot && (slot.is_a?(Integer) ? slot_names[slot] : slot.to_s) ] }
                            .to_set
    public_dates = public_events.not_deleted.where(held_on: range).distinct.pluck(:held_on).to_set
    counts = private_events.not_deleted.where(held_on: range).group(:held_on, :slot).count

    range.each_with_object({}) do |date, map|
      map[date] = SLOT_LABELS.keys.index_with do |slot|
        next false unless private_bookable_slot?(date, slot)
        next false unless private_booking_open?(date)
        next false if blocked.include?([ date, slot ]) || blocked.include?([ date, nil ])
        next false if slot == "soir" && public_dates.include?(date)

        counts.fetch([ date, slot ], 0) < capacity
      end
    end
  end

  # Une party publique est-elle programmée à cette date ? (Publiques = soirée.)
  def self.public_party_scheduled?(date)
    public_events.not_deleted.where(held_on: date).exists?
  end

  # Fournée qui PRÉPARE les pâtons d'une party privée (#170).
  #
  # Les pâtons se pétrissent à l'avance : une party du soir peut être servie par
  # la fournée du jour même, mais une party de midi, non — le matin même, la pâte
  # n'est pas prête. Et le calendrier de réservation accepte n'importe quel jour
  # de la semaine, y compris ceux sans fournée.
  #
  #   soir + une fournée existe ce jour-là → cette fournée
  #   sinon (midi, ou jour sans fournée)   → la dernière fournée qui précède
  #
  # Renvoie nil si aucune fournée ne précède la party : l'admin le signale
  # plutôt que de faire disparaître la party des écrans de production.
  def preparation_bake_day
    return nil unless kind_private_party? && held_on.present?

    if slot_soir?
      same_day = BakeDay.find_by(baked_on: held_on)
      return same_day if same_day
    end

    BakeDay.where(baked_on: ...held_on).order(baked_on: :desc).first
  end

  # Réciproque de `preparation_bake_day`, en une requête : les parties privées
  # que CETTE fournée doit préparer.
  #
  # Soit N la fournée suivante. `bake_day` prépare :
  #   - les parties du SOIR tenues le jour même ;
  #   - toutes les parties tenues strictement entre les deux fournées ;
  #   - les parties de MIDI tenues le jour de N (N ne prend que ses soirs).
  # Sans fournée suivante, tout ce qui vient après lui revient.
  scope :prepared_by, lambda { |bake_day|
    next none if bake_day&.baked_on.blank?

    date = bake_day.baked_on
    next_date = BakeDay.where("baked_on > ?", date).order(:baked_on).limit(1).pick(:baked_on)

    scope = private_events.not_deleted
    evening = scope.where(held_on: date, slot: slots[:soir])

    between =
      if next_date
        scope.where("held_on > ? AND held_on < ?", date, next_date)
             .or(scope.where(held_on: next_date, slot: slots[:midi]))
      else
        scope.where("held_on > ?", date)
      end

    evening.or(between).order(:held_on, :slot)
  }

  def slot_label
    SLOT_LABELS[slot] || "—"
  end

  # Places consommées d'un événement PUBLIC : somme des pâtons (adulte + enfant)
  # des commandes non annulées. Les commandes :pending comptent — elles
  # réservent la place le temps du paiement (même logique que la capacité des
  # fournées), et sont libérées par ExpireStalePendingOrdersJob si abandonnées.
  def seats_taken
    orders.where.not(status: Order.statuses[:cancelled]).joins(:order_items).sum(:qty)
  end

  # Places restantes (nil si pas de jauge — privé ou historique).
  def seats_remaining
    return nil if capacity.nil?

    [ capacity - seats_taken, 0 ].max
  end

  # Ventes importées en agrégé (ex. BilletWeb) plutôt que par commandes du site.
  def historical?
    historical_source.present?
  end

  # Frais BilletWeb saisis en euros dans l'admin, stockés en cents.
  def historical_fees_euros
    return nil if historical_fees_cents.nil?

    (historical_fees_cents / 100.0).round(2)
  end

  def historical_fees_euros=(value)
    self.historical_fees_cents = value.to_s.blank? ? nil : (value.to_f * 100).round
  end

  # Inscriptions ouvertes pour un événement PUBLIC ?
  def registration_open?
    return false unless kind_public_party? && active?

    registration_closes_at.nil? || registration_closes_at.future?
  end
end
