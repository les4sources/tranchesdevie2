class ConvertPanificationRatiosToDoughBasis < ActiveRecord::Migration[8.0]
  # Décision boulangers (réunion du 25/08/2026) : les QUATRE ingrédients sont
  # désormais des fractions de la PÂTE, plus des pourcentages boulangers.
  # Avant : eau et sel se calculaient sur la farine, farine et levain sur la pâte.
  LEGACY = { flour: 0.5556, water: 0.655, salt: 0.022, levain: 0.12095 }.freeze
  BAKERS = { flour: 0.532, water: 0.391, salt: 0.012, levain: 0.120 }.freeze

  def up
    # Les farines encore sur les valeurs historiques globales (jamais retouchées
    # depuis #88) prennent le ratio donné par les boulangers. Celles que les
    # boulangers ont personnalisées gardent leur recette : on convertit
    # seulement la BASE de l'eau et du sel (× farine/pâte), à grammes constants.
    customized_ids = select_values(sanitize([
      "SELECT id FROM flours WHERE flour_ratio <> ? OR water_ratio <> ? OR salt_ratio <> ? OR levain_ratio <> ?",
      LEGACY[:flour], LEGACY[:water], LEGACY[:salt], LEGACY[:levain]
    ]))

    if customized_ids.any?
      execute(sanitize([
        "UPDATE flours SET water_ratio = ROUND(water_ratio * flour_ratio, 5), " \
        "salt_ratio = ROUND(salt_ratio * flour_ratio, 5) WHERE id IN (?)",
        customized_ids
      ]))
    end

    execute(sanitize([
      "UPDATE flours SET flour_ratio = ?, water_ratio = ?, salt_ratio = ?, levain_ratio = ? " \
      "WHERE id NOT IN (?)",
      BAKERS[:flour], BAKERS[:water], BAKERS[:salt], BAKERS[:levain],
      customized_ids.presence || [ -1 ]
    ]))

    change_column_default :flours, :flour_ratio, from: LEGACY[:flour], to: BAKERS[:flour]
    change_column_default :flours, :water_ratio, from: LEGACY[:water], to: BAKERS[:water]
    change_column_default :flours, :salt_ratio, from: LEGACY[:salt], to: BAKERS[:salt]
    change_column_default :flours, :levain_ratio, from: LEGACY[:levain], to: BAKERS[:levain]
  end

  def down
    # Retour à la base « pourcentage boulanger » : eau et sel repassent sur la
    # farine. Les farines portant le ratio boulangers reprennent l'historique.
    execute(sanitize([
      "UPDATE flours SET flour_ratio = ?, water_ratio = ?, salt_ratio = ?, levain_ratio = ? " \
      "WHERE flour_ratio = ? AND water_ratio = ? AND salt_ratio = ? AND levain_ratio = ?",
      LEGACY[:flour], LEGACY[:water], LEGACY[:salt], LEGACY[:levain],
      BAKERS[:flour], BAKERS[:water], BAKERS[:salt], BAKERS[:levain]
    ]))

    execute(sanitize([
      "UPDATE flours SET water_ratio = ROUND(water_ratio / flour_ratio, 5), " \
      "salt_ratio = ROUND(salt_ratio / flour_ratio, 5) " \
      "WHERE flour_ratio > 0 AND NOT (flour_ratio = ? AND water_ratio = ? AND salt_ratio = ? AND levain_ratio = ?)",
      LEGACY[:flour], LEGACY[:water], LEGACY[:salt], LEGACY[:levain]
    ]))

    change_column_default :flours, :flour_ratio, from: BAKERS[:flour], to: LEGACY[:flour]
    change_column_default :flours, :water_ratio, from: BAKERS[:water], to: LEGACY[:water]
    change_column_default :flours, :salt_ratio, from: BAKERS[:salt], to: LEGACY[:salt]
    change_column_default :flours, :levain_ratio, from: BAKERS[:levain], to: LEGACY[:levain]
  end

  private

  def sanitize(array)
    ActiveRecord::Base.send(:sanitize_sql_array, array)
  end
end
