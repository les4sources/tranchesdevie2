class CreateInvoices < ActiveRecord::Migration[8.0]
  def change
    create_table :invoices do |t|
      # Numérotation séquentielle annuelle, ex. « FAC-2026-0001 » (unique).
      t.string :number, null: false
      t.references :customer, null: false, foreign_key: true

      # Date d'émission de la facture.
      t.date :issued_on, null: false

      # Période couverte (factures mensuelles groupées). Nul pour une facture
      # portant sur une seule commande.
      t.date :period_start
      t.date :period_end

      # Montants figés à l'émission (en cents). `subtotal_cents` = HT,
      # `vat_cents` = TVA, `total_cents` = TTC. Avec un taux de TVA à 0
      # (défaut), HT == TTC.
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :vat_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0

      # Taux de TVA appliqué (en pourcentage, ex. 6.0). Paramétrable — voir
      # note TVA de #38 ; 0 par défaut, ne bloque jamais la génération.
      t.decimal :vat_rate, precision: 5, scale: 2, null: false, default: 0

      t.timestamps
    end

    add_index :invoices, :number, unique: true
    add_index :invoices, :issued_on

    # Commandes couvertes par la facture. Une facture « commande unique » a une
    # seule ligne ; une facture « période » en a plusieurs. Le couple
    # (invoice, order) est unique.
    create_table :invoice_orders do |t|
      t.references :invoice, null: false, foreign_key: true
      t.references :order, null: false, foreign_key: true

      t.timestamps
    end

    add_index :invoice_orders, [ :invoice_id, :order_id ], unique: true
  end
end
