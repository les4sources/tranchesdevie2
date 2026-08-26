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
  end
end
