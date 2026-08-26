class CreateWorkshops < ActiveRecord::Migration[8.0]
  def change
    # Ateliers (#208) : atelier pain, atelier pizza… Un revenu complémentaire
    # régulier qui n'existait nulle part dans l'application.
    create_table :workshops do |t|
      t.date :held_on, null: false
      t.string :title, null: false
      t.text :description
      t.text :notes
      t.integer :revenue_cents, null: false, default: 0

      t.timestamps
    end

    add_index :workshops, :held_on

    # Animateurs de l'atelier. Même forme que `bake_day_artisans` : c'est le
    # mécanisme de groupe existant qu'on réutilise, pas un second.
    create_table :workshop_artisans do |t|
      t.references :workshop, null: false, foreign_key: true
      t.references :artisan, null: false, foreign_key: true

      t.timestamps
    end

    add_index :workshop_artisans, [ :workshop_id, :artisan_id ], unique: true
  end
end
