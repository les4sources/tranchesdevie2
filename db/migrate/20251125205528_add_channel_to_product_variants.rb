class AddChannelToProductVariants < ActiveRecord::Migration[8.0]
  def change
    add_column :product_variants, :channel, :string, default: 'store', null: false
  end
end
