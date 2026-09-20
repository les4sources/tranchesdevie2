# Remboursement PARTIEL d'une commande livrée (#remboursement-partiel).
#
# Le cas réel : la cliente rentre avec cinq froments aux graines au lieu de six,
# sans son rond cuit sur pierre, et avec un second épeautre à la place du
# noix-figue. Les boulangers décident de rembourser trois lignes et d'offrir le
# quatrième pain. `RefundService` ne sait faire que tout ou rien, après quoi la
# vente disparaît — ici on rend un morceau et la commande reste ce qu'elle est :
# livrée, encaissée, partiellement remboursée.
#
# Différences structurelles avec RefundService, toutes voulues :
#   - le `status` de la commande ne bouge pas (elle a bien été retirée) ;
#   - le `payment_status` non plus (« remboursé » veut dire remboursé en entier) ;
#   - le cut-off n'a rien à y faire : le problème se découvre APRÈS le retrait.
class PartialRefundService
  attr_reader :errors, :partial_refund

  # `lines` : { order_item_id => qty }. `amount_cents` : montant imposé par le
  # boulanger, qui prime sur le calcul (geste commercial, arrondi) ; à défaut on
  # rembourse le net des lignes cochées.
  def initialize(order, lines:, channel:, amount_cents: nil, reason: nil, order_issue: nil)
    @order = order
    @lines = normalize_lines(lines)
    @channel = channel.to_s
    @amount_cents = amount_cents
    @reason = reason.presence
    @order_issue = order_issue
    @errors = []
  end

  def call
    return false unless valid?

    ActiveRecord::Base.transaction do
      @partial_refund = PartialRefund.create!(
        order: @order,
        order_issue: @order_issue,
        amount_cents: amount,
        channel: @channel,
        reason: @reason
      )
      create_refund_items!
      # Le mouvement d'argent vit DANS la transaction : un échec Stripe annule
      # l'enregistrement, et l'enregistrement ne survit jamais seul à un
      # remboursement qui n'a pas eu lieu.
      execute_movement!
      @order_issue&.resolve!(by: "remboursement")
    end

    notify_customer
    true
  rescue Stripe::StripeError => e
    @errors << "Erreur Stripe : #{e.message}"
    Sentry.capture_exception(e) if defined?(Sentry)
    false
  rescue ActiveRecord::RecordInvalid => e
    @errors << e.record.errors.full_messages.to_sentence
    false
  end

  # Montant proposé (en cents) pour un jeu de lignes, sans rien exécuter — c'est
  # ce que l'admin affiche à côté des cases à cocher. NET : la remise du client
  # est déjà répartie sur les lignes (cf. `Order.net_cents_by_item`).
  def self.proposed_amount_cents(order, lines)
    net_by_item = order.net_cents_by_item
    order.order_items.sum do |item|
      qty = lines[item.id].to_i
      next 0 unless qty.positive?

      line_net = net_by_item[item.id].to_i
      qty >= item.qty ? line_net : (line_net * qty / item.qty.to_f).round
    end
  end

  private

  def amount
    @amount ||= @amount_cents.presence&.to_i || self.class.proposed_amount_cents(@order, @lines)
  end

  def normalize_lines(lines)
    (lines || {}).to_h.each_with_object({}) do |(item_id, qty), hash|
      hash[item_id.to_i] = qty.to_i if qty.to_i.positive?
    end
  end

  def order_items_by_id
    @order_items_by_id ||= @order.order_items.index_by(&:id)
  end

  # Quantité déjà remboursée pour une ligne, tous remboursements partiels
  # confondus : on ne rembourse pas deux fois le même pain.
  def already_refunded_qty
    @already_refunded_qty ||= @order.refunded_qty_by_item
  end

  def valid?
    @errors = []

    @errors << "Cette commande n'est pas remboursable" unless @order.can_be_partially_refunded?
    @errors << "Canal de remboursement inconnu" unless PartialRefund.channels.key?(@channel)
    @errors << "Sélectionne au moins un article" if @lines.empty?

    @lines.each do |item_id, qty|
      item = order_items_by_id[item_id]
      if item.nil?
        @errors << "Article introuvable dans cette commande"
        next
      end

      remaining = item.qty - already_refunded_qty.fetch(item_id, 0)
      @errors << "#{item.full_name} : #{qty} unité(s) demandée(s), #{remaining} remboursable(s)" if qty > remaining
    end

    @errors << "Le montant doit être positif" unless amount.positive?
    if amount > @order.refundable_remaining_cents
      @errors << "Montant supérieur au remboursable restant (#{format_euros(@order.refundable_remaining_cents)})"
    end

    validate_channel_availability

    @errors.empty?
  end

  def validate_channel_availability
    case @channel
    when "stripe"
      @errors << "Aucun paiement Stripe sur cette commande" unless stripe_refundable?
    when "wallet"
      @errors << "Ce client n'a pas de portefeuille" unless @order.customer.present?
    end
  end

  def stripe_refundable?
    @order.payment.present? && @order.payment.succeeded?
  end

  # Répartit le montant final sur les lignes cochées au prorata de leur net :
  # la somme des lignes égale EXACTEMENT le montant remboursé, même quand le
  # boulanger a forcé un montant rond.
  def create_refund_items!
    entries = @lines.map do |item_id, qty|
      item = order_items_by_id[item_id]
      { item: item, qty: qty, weight: self.class.proposed_amount_cents(@order, { item_id => qty }) }
    end

    shares = distribute(entries.map { |entry| entry[:weight] }, amount)

    entries.each_with_index do |entry, index|
      @partial_refund.partial_refund_items.create!(
        order_item: entry[:item],
        qty: entry[:qty],
        amount_cents: shares[index]
      )
    end
  end

  def distribute(weights, total)
    return [] if weights.empty?

    sum = weights.sum
    return Array.new(weights.size) { |index| index.zero? ? total : 0 } if sum.zero?

    shares = weights.map { |weight| (total * weight / sum.to_f).round }
    shares[weights.each_with_index.max_by { |weight, _| weight }.last] += total - shares.sum
    shares
  end

  def execute_movement!
    case @channel
    when "stripe" then refund_on_stripe!
    when "wallet" then credit_wallet!
    when "cash"   then nil # Le boulanger rend les pièces ; l'app n'en garde que la trace.
    end
  end

  def refund_on_stripe!
    refund = Stripe::Refund.create({
      payment_intent: @order.payment.stripe_payment_intent_id,
      amount: amount
    })

    unless RefundService::SUCCESSFUL_STRIPE_REFUND_STATUSES.include?(refund.status)
      raise Stripe::StripeError, "remboursement refusé (#{refund.failure_reason || refund.status})"
    end

    @partial_refund.update!(stripe_refund_id: refund.id)
  end

  def credit_wallet!
    wallet = @order.customer.wallet || @order.customer.create_wallet!
    transaction = WalletService.partial_refund_for_order(wallet: wallet, order: @order, amount_cents: amount)
    @partial_refund.update!(wallet_transaction: transaction)
  end

  def notify_customer
    OrderNotificationService.send_partial_refund(@partial_refund)
  rescue StandardError => e
    # L'argent est parti : un e-mail qui échoue ne doit pas faire croire à un
    # remboursement raté.
    Rails.logger.error("PartialRefundService notification: #{e.class} - #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end

  def format_euros(cents)
    format("%.2f €", cents / 100.0).tr(".", ",")
  end
end
