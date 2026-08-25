# frozen_string_literal: true

# Lecture des commandes party dans l'admin (#173).
#
# On passe toujours par la VARIANTE de chaque ligne (son produit, son nom) et
# jamais par une comparaison de prix : les tarifs bougent, la nomenclature non.
module Admin::PartyHelper
  # Nombre de pâtons d'une réservation privée — une boule par personne. La ligne
  # « forfait », unique par commande quel que soit le nombre de convives, n'est
  # pas un pâton.
  def party_paton_count(order)
    return 0 if order.nil?

    order.order_items.sum do |item|
      item.product_variant.product.pizza_party_role_party? ? item.qty : 0
    end
  end

  # Inscriptions d'une party publique ventilées adulte / enfant. Les variantes du
  # produit `pizza_party_role: :public_party` sont nommées « adulte » et
  # « enfant » (cf. db/seeds.rb) ; tout autre nom retombe dans :other, pour
  # qu'une variante ajoutée plus tard ne disparaisse pas silencieusement du total.
  def party_seat_counts(order)
    counts = { adults: 0, children: 0, other: 0 }
    return counts if order.nil?

    order.order_items.each do |item|
      variant = item.product_variant
      next unless variant.product.pizza_party_role_public_party?

      case variant.name.to_s.downcase
      when /adulte/ then counts[:adults] += item.qty
      when /enfant/ then counts[:children] += item.qty
      else counts[:other] += item.qty
      end
    end

    counts
  end

  def party_seats_total(order)
    party_seat_counts(order).values.sum
  end

  # Le four est-il déjà chaud ce jour-là ? Les jours de boulangerie, le groupe
  # enfourne directement ; sinon il doit gérer ~3 h de chauffe.
  def party_oven_already_hot?(held_on)
    held_on.present? && BakeDay::COOKING_WDAYS.include?(held_on.wday)
  end
end
