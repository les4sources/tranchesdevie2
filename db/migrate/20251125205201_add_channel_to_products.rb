class AddChannelToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :channel, :string, default: 'store', null: false
  end
end
