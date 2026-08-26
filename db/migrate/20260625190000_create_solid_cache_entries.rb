# frozen_string_literal: true

# Crée la table `solid_cache_entries` dans la base PRIMAIRE.
#
# Contexte (500 sur /admin/reports/payouts) : Solid Cache était configuré sur une
# base séparée `cache` (config/cache.yml → `database: cache`) dont le schéma vit
# uniquement dans db/cache_schema.rb. Le déploiement Hatchbox ne lance que
# `db:migrate` sur la base primaire et ne charge jamais cache_schema.rb : la table
# n'a donc jamais été créée en production. Le premier appel à `Rails.cache`
# (StripePayoutReportService) levait alors `PG::UndefinedTable` → 500.
#
# On aligne Solid Cache sur Solid Queue, qui utilise déjà la connexion primaire et
# dont les tables vivent dans db/schema.rb. Avec config/cache.yml ne pointant plus
# vers une base séparée, cette migration suffit à rendre le cache fonctionnel.
#
# Schéma repris à l'identique de db/cache_schema.rb. Idempotente : ne fait rien si
# la table existe déjà (au cas où un db:prepare l'aurait créée).
class CreateSolidCacheEntries < ActiveRecord::Migration[8.0]
  def change
    return if table_exists?(:solid_cache_entries)

    create_table :solid_cache_entries do |t|
      t.binary   :key,        null: false, limit: 1024
      t.binary   :value,      null: false, limit: 536_870_912
      t.datetime :created_at, null: false
      t.integer  :key_hash,   null: false, limit: 8
      t.integer  :byte_size,  null: false, limit: 4

      t.index :byte_size,                name: "index_solid_cache_entries_on_byte_size"
      t.index [ :key_hash, :byte_size ], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
      t.index :key_hash, unique: true,   name: "index_solid_cache_entries_on_key_hash"
    end
  end
end
