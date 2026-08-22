class AddPartyFourSourcesBaseToProductVariants < ActiveRecord::Migration[8.0]
  # Base 4 Sources (en cents) d'une variante de PARTY PUBLIQUE (#pizza-parties) :
  # 3 € pour « adulte », 2 € pour « enfant ». La base boulangers en découle
  # (prix public − base 4 Sources). Nul pour toute variante non concernée.
  def change
    add_column :product_variants, :party_four_sources_base_cents, :integer
  end
end
