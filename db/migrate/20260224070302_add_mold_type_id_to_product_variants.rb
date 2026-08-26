# frozen_string_literal: true

class AddMoldTypeIdToProductVariants < ActiveRecord::Migration[8.0]
  def change
    add_reference :product_variants, :mold_type, null: true, foreign_key: true
  end
end
