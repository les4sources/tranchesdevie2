# Bascule vers le barème public (#pizza-parties). Les pizza parties publiques de
# juin/juillet étaient loggées par les boulangers en commandes internes « privées »
# à 5 €/boule (client « Boulangerie … »), ce qui fait double emploi avec l'import
# BilletWeb agrégé (barème public rétroactif). On neutralise ces 2 commandes pour
# que l'import public devienne la seule référence comptable de ces parties.
#
#   - Juin (TV-20260611-0009, Boulangerie Tranches de vie) : retire UNIQUEMENT la
#     ligne « 187 boules » (produit party privée), GARDE les pains du jour (46,50 €).
#   - Juillet (TV-20260716-0001, Boulangerie Party) : 100 % party → statut `cancelled`
#     (exclue de `completed` → disparaît du reporting, réversible).
#
# Idempotente et défensive : no-op si les commandes sont absentes (ex. base de test).
class NeutralizeBilletwebInternalPartyOrders < ActiveRecord::Migration[8.0]
  def up
    party_role = Product.pizza_party_roles[:party]

    if (june = Order.find_by(order_number: "TV-20260611-0009"))
      removed = remove_party_items(june, party_role)
      say "Juin TV-20260611-0009 : #{removed} ligne(s) party retirée(s), total → #{june.reload.total_cents} cents"
    end

    if (july = Order.find_by(order_number: "TV-20260716-0001")) && !july.cancelled?
      july.update_columns(status: Order.statuses[:cancelled], updated_at: Time.current)
      say "Juillet TV-20260716-0001 : statut → cancelled"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Neutralisation manuelle des commandes party internes — voir l'historique BilletWeb sur les party_events."
  end

  private

  # Retire les lignes de commande portant un produit « pizza party privée » et
  # recalcule le total à partir des lignes restantes (ne touche pas au total si
  # rien ne reste, pour ne pas violer total_cents > 0 — cas juin: pains restants).
  def remove_party_items(order, party_role)
    items = order.order_items.joins(product_variant: :product).where(products: { pizza_party_role: party_role })
    count = items.count
    return 0 if count.zero?

    items.destroy_all
    remaining = order.order_items.reload.sum { |item| item.unit_price_cents * item.qty }
    order.update_columns(total_cents: remaining, updated_at: Time.current) if remaining.positive?
    count
  end
end
