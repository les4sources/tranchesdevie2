# Page publique « Pizza Party publique » (/pizza-party-publique,
# #pizza-parties) : liste les événements créés par l'admin, avec places
# restantes et clôture des inscriptions. L'inscription (variantes adulte /
# enfant) rejoint le panier rattachée à SON événement, puis le checkout crée
# une commande party via PublicPartyRegistrationService.
class PublicPartiesController < ApplicationController
  def index
    @product = Product.not_deleted.active.store_channel.find_by(pizza_party_role: :public_party)
    @variants = @product&.product_variants&.active&.store_channel
                        &.visible_to_customer(current_customer)&.order(price_cents: :desc)

    @events = PartyEvent.public_events.upcoming.where(active: true)
                        .where(historical_source: nil)

    # Panier qui EMPÊCHE l'inscription : une commande party ne se mélange ni au
    # pain ni à une party privée, et le client ne pouvait le découvrir qu'en
    # cliquant « Ajouter » (le refus arrivait après coup, sans rien lui dire de
    # quoi faire). Le cookie de session vit un an : un pain oublié il y a des
    # semaines bloque encore l'inscription aujourd'hui. On l'annonce AVANT.
    @blocking_cart_count = non_public_items_in_cart? ? cart_item_count : 0
  end

  private

  # Le panier contient-il autre chose qu'une inscription à une party publique ?
  def non_public_items_in_cart?
    (Product.pizza_party_roles_in_cart(session[:cart]) - [ "public_party" ]).any?
  end

  def cart_item_count
    Array(session[:cart]).sum { |item| item["qty"].to_i }
  end
end
