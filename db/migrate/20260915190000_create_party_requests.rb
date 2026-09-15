class CreatePartyRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :party_requests do |t|
      t.references :customer, null: false, foreign_key: true
      # Nul tant que la demande n'est pas validée : l'Order (et le PartyEvent qui
      # va avec) ne naît qu'à ce moment-là. Une demande refusée ne laisse donc
      # aucune trace dans les tables comptables.
      t.references :order, foreign_key: true

      t.date :held_on, null: false
      t.integer :slot, null: false
      # Nombre ESTIMÉ par le client à la demande — c'est sur lui que le boulanger
      # décide. Le nombre facturé est celui confirmé au paiement (order_items).
      t.integer :estimated_persons, null: false
      t.boolean :forfait, null: false, default: true
      t.text :customer_note, null: false
      t.string :group_name

      t.integer :state, null: false, default: 0
      t.string :public_token, limit: 24, null: false

      # Décision de la boulangerie.
      t.datetime :decided_at
      t.string :decided_by
      t.text :decision_reason

      # Relance interne (une seule par demande, cf. ISC-24).
      t.datetime :reminded_at

      t.timestamps
    end

    add_index :party_requests, :public_token, unique: true
    add_index :party_requests, :state
    add_index :party_requests, [ :held_on, :slot ]

    # Lignes figées à la demande : prix unitaires et remise gelés, pour qu'un
    # changement de tarif ou de groupe entre la demande et le paiement ne change
    # rien à ce qui a été annoncé (ISC-28).
    create_table :party_request_items do |t|
      t.references :party_request, null: false, foreign_key: true
      t.references :product_variant, null: false, foreign_key: true
      t.integer :qty, null: false
      t.integer :unit_price_cents, null: false
      t.integer :discount_cents, null: false, default: 0
      t.timestamps
    end
  end
end
