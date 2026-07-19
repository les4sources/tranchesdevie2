class EventsController < ApplicationController
  # Page publique « Événements » (#pizza-parties) : la réservation d'une pizza
  # party privée vit ICI, hors du catalogue produits normal. Elle réutilise le
  # flux panier → checkout existant (le forfait 40 € est auto-synchronisé par
  # PizzaPartyForfaitService dès qu'un pâton party est au panier).
  def index
    @product = Product.not_deleted.active.store_channel
                      .find_by(pizza_party_role: :party)
    return if @product.nil?

    @variants = @product.product_variants.active.store_channel
                        .visible_to_customer(current_customer).order(:name)
    @selected_variant = @variants.first
  end
end
