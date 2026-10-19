# « D'où viennent nos mangeurs ? » (retour Michael 19/10/2026). Ventile les
# clients qui ont acheté sur la période par village déclaré
# (`customers.locality`), avec leurs commandes et le CA. Les clients sans
# village forment une ligne « Non renseigné » à part, pour mesurer la
# couverture de la réponse.
#
# Même assiette que le reste du reporting daté : Order.completed, rattaché au
# jour de cuisson (`in_bake_day_range`).
#
# Usage :
#   report = CustomerOriginReportService.new(start_date:, end_date:).call
#   report.rows                 # => [ Row(locality:, customers_count:, ...), ... ]
#   report.unknown              # => Row des clients sans village (ou nil)
class CustomerOriginReportService
  Row = Struct.new(:locality, :customers_count, :orders_count, :revenue_cents, keyword_init: true)

  Report = Struct.new(:rows, :unknown, :customers_count, :known_customers_count, keyword_init: true) do
    # Part des acheteurs de la période qui ont indiqué leur village (0..100).
    def coverage_percent
      return 0 if customers_count.zero?

      (known_customers_count * 100.0 / customers_count).round
    end
  end

  def initialize(start_date:, end_date:)
    @start_date = start_date
    @end_date = end_date
  end

  def call
    locality_key = Arel.sql("lower(customers.locality)")

    grouped = Order.completed
                   .in_bake_day_range(@start_date, @end_date)
                   .joins(:customer)
                   .group(locality_key)
                   .pluck(
                     locality_key,
                     Arel.sql("MIN(customers.locality)"),
                     Arel.sql("COUNT(DISTINCT customers.id)"),
                     Arel.sql("COUNT(DISTINCT orders.id)"),
                     Arel.sql("COALESCE(SUM(orders.total_cents), 0)")
                   )

    rows = []
    unknown = nil
    grouped.each do |key, name, customers_count, orders_count, revenue_cents|
      row = Row.new(locality: name, customers_count: customers_count.to_i,
                    orders_count: orders_count.to_i, revenue_cents: revenue_cents.to_i)
      key.nil? ? unknown = row : rows << row
    end

    rows.sort_by! { |row| [ -row.customers_count, -row.revenue_cents, row.locality.to_s ] }
    known = rows.sum(&:customers_count)

    Report.new(rows: rows, unknown: unknown,
               customers_count: known + (unknown&.customers_count || 0),
               known_customers_count: known)
  end
end
