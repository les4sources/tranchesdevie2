# Paiement différé d'une réservation de Pizza party déjà validée (#pizza-parties).
#
# Ce service porte les deux gestes qui n'existent nulle part ailleurs dans l'app :
#
# 1. **Confirmer le nombre de participants.** La demande portait une estimation ;
#    c'est ici que le client arrête le chiffre réel (un pâton par personne). Le
#    total se recalcule aux prix UNITAIRES FIGÉS à la demande — jamais aux tarifs
#    du jour, sans quoi un changement de prix entre la demande et le paiement
#    trahirait le montant annoncé.
#
# 2. **Tenir le PaymentIntent aligné sur la commande.** Le client peut rouvrir la
#    page et confirmer un autre nombre : sans mise à jour du montant côté Stripe,
#    il paierait le chiffre de sa première visite. Le PI est donc réutilisé tant
#    qu'il est vivant, et son montant suit la commande dans la même transaction.
class PartyPaymentService
  # Statuts d'un PaymentIntent qu'on peut encore modifier et réutiliser.
  REUSABLE_PI_STATUSES = %w[requires_payment_method requires_confirmation requires_action].freeze

  attr_reader :order, :errors

  def initialize(order)
    @order = order
    @errors = []
  end

  # Applique le nombre confirmé de participants et renvoie le total dû.
  def confirm_headcount!(persons)
    persons = persons.to_i

    if persons < 1
      @errors << "Merci d'indiquer au moins un participant."
      return false
    end

    request = @order.party_request

    if request.nil?
      @errors << "Cette réservation ne se règle pas en ligne."
      return false
    end

    capacity_errors = capacity_errors_for(persons)

    if capacity_errors.any?
      @errors.concat(capacity_errors)
      return false
    end

    ActiveRecord::Base.transaction do
      apply_headcount(request, persons)
      @order.reload
    end

    @order.total_cents
  end

  # La fournée qui pétrira ces pâtons supporte-t-elle le nombre confirmé ?
  #
  # La cible est la fournée DU JOUR MÊME (`baked_on == held_on`) et non
  # `preparation_bake_day`, qui retombe sur la fournée précédente quand celle du
  # jour n'existe pas encore : on contrôlerait alors la capacité d'un mardi déjà
  # cuit pour une party du vendredi. Les fournées ne sont créées qu'à quelques
  # jours d'avance : quand celle du jour n'existe pas, on ne bloque pas le
  # paiement — on le trace.
  def capacity_errors_for(persons)
    bake_day = BakeDay.find_by(baked_on: @order.party_event&.held_on)

    if bake_day.nil?
      Rails.logger.info("PartyPayment: aucune fournée le #{@order.party_event&.held_on} — capacité non vérifiée (commande #{@order.id})")
      return []
    end

    paton_variant = @order.order_items.includes(product_variant: :product)
                          .find { |item| paton?(item) }&.product_variant
    return [] if paton_variant.nil?

    result = BakeCapacityService.new(bake_day).cart_fits?([ { "product_variant_id" => paton_variant.id, "qty" => persons } ])
    result[:fits] ? [] : result[:errors]
  end

  # Client secret d'un PaymentIntent dont le montant correspond à la commande.
  def payment_intent_client_secret
    intent = reusable_intent

    if intent
      Stripe::PaymentIntent.update(intent.id, amount: @order.total_cents) if intent.amount != @order.total_cents
      return Stripe::PaymentIntent.retrieve(intent.id).client_secret
    end

    intent = Stripe::PaymentIntent.create(
      amount: @order.total_cents,
      currency: "eur",
      automatic_payment_methods: { enabled: true },
      metadata: {
        order_id: @order.id,
        party_event_id: @order.party_event_id,
        party_request_id: @order.party_request&.id
      }.compact
    )

    @order.update!(payment_intent_id: intent.id)
    intent.client_secret
  rescue Stripe::StripeError => e
    @errors << "Le paiement est momentanément indisponible. Réessaie dans un instant."
    Rails.logger.error("PartyPayment: Stripe #{e.class} pour commande #{@order.id}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    nil
  end

  private

  # Met la ligne « pâtons » au nombre confirmé, laisse le forfait à 1, et
  # recalcule le total depuis les lignes figées de la demande.
  def apply_headcount(request, persons)
    request.party_request_items.includes(product_variant: :product).each do |item|
      next unless paton?(item)

      item.update!(qty: persons)
    end

    request.reload

    @order.order_items.includes(product_variant: :product).each do |order_item|
      next unless paton?(order_item)

      order_item.update!(qty: persons)
    end

    @order.update!(total_cents: request.party_request_items.sum(&:total_cents))
  end

  def paton?(item)
    item.product_variant.product.pizza_party_role_party?
  end

  # PaymentIntent encore modifiable. Un PI abouti (`succeeded`) ou annulé ne se
  # réutilise pas : on en crée un neuf, l'ancien étant déjà hors jeu.
  def reusable_intent
    return nil if @order.payment_intent_id.blank?

    intent = Stripe::PaymentIntent.retrieve(@order.payment_intent_id)
    REUSABLE_PI_STATUSES.include?(intent.status) ? intent : nil
  rescue Stripe::StripeError => e
    Rails.logger.warn("PartyPayment: PI #{@order.payment_intent_id} illisible: #{e.message}")
    nil
  end
end
