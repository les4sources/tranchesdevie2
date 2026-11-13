class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product_variant
  # Fournée d'enfournement (#194). Optionnelle : « non affectée » est un
  # état normal, et c'est celui qu'on rend visible aux boulangers.
  belongs_to :batch, optional: true

  # Renseigné sur les seules lignes CALCULÉES des pains de Camembert Party
  # (`CamembertBreads#order_items`), jamais enregistrées : leur fournée se lit
  # et s'écrit sur l'événement (`PartyEvent#bread_batch_id`).
  attr_accessor :camembert_party_event

  def camembert_bread?
    camembert_party_event.present?
  end

  validates :qty, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :unit_price_cents, presence: true, numericality: { greater_than: 0 }

  # Libellé complet « Produit — Variante » (ex. « Pain froment — Petit 600 g »),
  # utilisé pour le détail des commandes de la facturation (#98).
  def full_name
    "#{product_variant.product.name} — #{product_variant.name}"
  end

  def subtotal_cents
    qty * unit_price_cents
  end

  def unit_price_euros
    (unit_price_cents / 100.0).round(2)
  end

  def subtotal_euros
    (subtotal_cents / 100.0).round(2)
  end
end
