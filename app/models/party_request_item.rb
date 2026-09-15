# Ligne d'une demande de Pizza party, avec son prix unitaire FIGÉ (#pizza-parties).
#
# Le prix est copié au moment de la demande et plus jamais relu depuis la
# variante : c'est ce qui garantit qu'un changement de tarif, ou de groupe de
# remise du client, entre la demande et le paiement ne change pas ce qui lui a
# été annoncé. Seule la QUANTITÉ bouge, confirmée par le client au paiement.
class PartyRequestItem < ApplicationRecord
  belongs_to :party_request
  belongs_to :product_variant

  validates :qty, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def total_cents
    qty * unit_price_cents - discount_cents
  end
end
