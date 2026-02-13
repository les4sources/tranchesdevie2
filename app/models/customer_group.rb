class CustomerGroup < ApplicationRecord
  belongs_to :customer
  belongs_to :group

  validates :group_id, uniqueness: { scope: :customer_id }
end
