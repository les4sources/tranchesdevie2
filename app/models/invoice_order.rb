# Lien entre une facture et une commande couverte (#38).
#
# Une facture « commande unique » a une seule ligne ; une facture « période »
# (mensuelle groupée, clients pro) en a une par commande de la période.
class InvoiceOrder < ApplicationRecord
  belongs_to :invoice
  belongs_to :order

  validates :order_id, uniqueness: { scope: :invoice_id }
end
