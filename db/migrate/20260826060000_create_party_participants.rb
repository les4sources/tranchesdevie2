class CreatePartyParticipants < ActiveRecord::Migration[8.0]
  def change
    # Liste NOMINATIVE des participants d'une party historique (#206).
    #
    # Purement documentaire : savoir qui est venu, pouvoir recontacter. La
    # comptabilité de ces événements vient de l'agrégat `historical_*` porté par
    # `party_event` — aucun `Order` n'est créé ici, et rien de cette table
    # n'entre dans un calcul de revenu.
    create_table :party_participants do |t|
      t.references :party_event, null: false, foreign_key: true
      t.string :first_name
      t.string :last_name
      t.string :email
      t.string :ticket_kind, null: false          # "adult" | "child"
      t.string :external_reference                # n° de commande de la billetterie
      t.string :external_ticket_label             # libellé « Tarif » d'origine, tel quel
      t.integer :price_cents
      t.boolean :external_paid, default: false, null: false

      t.timestamps
    end

    # Idempotence de l'import : une même personne d'une même commande d'un même
    # événement ne s'insère qu'une fois, quel que soit le nombre d'exécutions.
    add_index :party_participants,
              [ :party_event_id, :external_reference, :last_name, :first_name, :ticket_kind ],
              unique: true,
              name: "index_party_participants_uniqueness"
  end
end
