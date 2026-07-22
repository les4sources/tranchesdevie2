class EventsController < ApplicationController
  # Page publique « Événements » (#pizza-parties) : les pizza parties (privée ET
  # publique) se réservent ICI, hors du catalogue produits normal. Elles
  # réutilisent le flux panier → checkout existant (le forfait 40 € de la party
  # privée est auto-synchronisé par PizzaPartyForfaitService).
  def index
    @product = party_product(:party)
    @variants = variants_for(@product)
    @selected_variant = @variants&.first

    # Calendrier des disponibilités de la party privée : 8 semaines glissantes,
    # créneaux midi/soir (blocages admin, parties publiques du soir et capacité
    # déjà déduits). La sélection est revalidée à l'ajout panier et au checkout.
    if @product && @selected_variant
      @availability_start = Date.current + 1.day
      @party_availability = PartyEvent.private_availability(@availability_start..(@availability_start + 8.weeks))
    end

    @public_product = party_product(:public_party)
    @public_variants = variants_for(@public_product)
  end

  private

  def party_product(role)
    Product.not_deleted.active.store_channel.find_by(pizza_party_role: role)
  end

  def variants_for(product)
    return nil if product.nil?

    variants = product.product_variants.active.store_channel
                      .visible_to_customer(current_customer).order(:name)
    variants.presence
  end
end
