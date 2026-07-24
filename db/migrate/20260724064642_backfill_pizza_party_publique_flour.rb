class BackfillPizzaPartyPubliqueFlour < ActiveRecord::Migration[8.0]
  # Le produit « Pizza party publique » a été créé sans répartition de farine :
  # ses boules n'apparaissaient dans aucune stat « par type de farine ». On
  # aligne sur le produit privé (Froment (pâtons) 100 %). Idempotent.
  def up
    product = Product.find_by(name: "Pizza party publique")
    return if product.nil? || product.product_flours.exists?

    flour = Flour.find_by(name: "Froment (pâtons)")
    return if flour.nil?

    ProductFlour.create!(product: product, flour: flour, percentage: 100)
  end

  def down
    # Rien : la répartition ajoutée est une correction de données.
  end
end
