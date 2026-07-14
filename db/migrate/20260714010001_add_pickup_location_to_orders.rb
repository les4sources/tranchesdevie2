class AddPickupLocationToOrders < ActiveRecord::Migration[8.0]
  # Rattachement rétroactif : jusqu'ici toute commande était implicitement
  # retirée aux 4 Sources. On crée le lieu par défaut, on l'ouvre sur toutes les
  # fournées existantes, on backfill les commandes, et SEULEMENT ensuite on pose
  # la contrainte NOT NULL (sans quoi la migration échouerait sur une base ayant
  # déjà des commandes).
  #
  # Les modèles ne sont pas utilisés ici (une migration doit rester valable même
  # si le code applicatif évolue) : tout passe par du SQL.
  def up
    add_reference :orders, :pickup_location, null: true, foreign_key: true

    seed_pickup_locations
    open_default_on_every_bake_day
    backfill_orders

    change_column_null :orders, :pickup_location_id, false
  end

  def down
    remove_reference :orders, :pickup_location, foreign_key: true
  end

  private

  def seed_pickup_locations
    execute(<<~SQL.squish)
      INSERT INTO pickup_locations (name, description, "default", position, created_at, updated_at)
      SELECT 'Les 4 Sources',
             'Retrait à la boulangerie des 4 Sources, sur le site de Bauche.',
             true, 0, NOW(), NOW()
      WHERE NOT EXISTS (SELECT 1 FROM pickup_locations WHERE name = 'Les 4 Sources')
    SQL

    execute(<<~SQL.squish)
      INSERT INTO pickup_locations (name, description, "default", position, created_at, updated_at)
      SELECT 'Marché d''Anhée',
             'Retrait sur notre étal, les jours de marché à Anhée.',
             false, 1, NOW(), NOW()
      WHERE NOT EXISTS (SELECT 1 FROM pickup_locations WHERE name = 'Marché d''Anhée')
    SQL
  end

  def open_default_on_every_bake_day
    execute(<<~SQL.squish)
      INSERT INTO bake_day_pickup_locations (bake_day_id, pickup_location_id, created_at, updated_at)
      SELECT bake_days.id, #{default_location_id_sql}, NOW(), NOW()
      FROM bake_days
      ON CONFLICT DO NOTHING
    SQL
  end

  def backfill_orders
    execute(<<~SQL.squish)
      UPDATE orders
      SET pickup_location_id = #{default_location_id_sql}
      WHERE pickup_location_id IS NULL
    SQL
  end

  def default_location_id_sql
    "(SELECT id FROM pickup_locations WHERE \"default\" = true AND deleted_at IS NULL LIMIT 1)"
  end
end
