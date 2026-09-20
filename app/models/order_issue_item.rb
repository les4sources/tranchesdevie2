class OrderIssueItem < ApplicationRecord
  belongs_to :order_issue
  belongs_to :order_item

  validates :qty, numericality: { only_integer: true, greater_than: 0 }
  validate :qty_within_ordered_quantity

  private

  # On ne signale pas trois pains manquants sur une ligne qui n'en comptait que
  # deux : le formulaire le borne déjà, le serveur le garantit.
  def qty_within_ordered_quantity
    return if order_item.nil? || qty.nil?

    errors.add(:qty, "dépasse la quantité commandée") if qty > order_item.qty
  end
end
