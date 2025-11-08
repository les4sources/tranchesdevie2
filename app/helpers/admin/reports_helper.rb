module Admin::ReportsHelper
  def reports_currency(cents)
    number_to_currency(cents.to_f / 100, unit: "€", separator: ",", delimiter: "")
  end

  def revenue_share(total_cents, overall_cents)
    return 0 if overall_cents.to_f.zero?

    ((total_cents.to_f / overall_cents.to_f) * 100).round(1)
  end

  def weekday_sales_chart_config(weekday_data)
    labels = weekday_data.map { |entry| weekday_label(entry[:weekday]) }
    revenue_values = weekday_data.map { |entry| (entry[:total_cents].to_f / 100).round(2) }

    {
      type: 'bar',
      data: {
        labels: labels,
        datasets: [
          {
            label: "Chiffre d'affaires (€)",
            data: revenue_values,
            backgroundColor: '#3b82f6'
          }
        ]
      },
      options: {
        responsive: true,
        plugins: {
          legend: { display: false }
        },
        scales: {
          y: {
            beginAtZero: true
          }
        }
      }
    }
  end

  def monthly_sales_chart_config(monthly_data)
    labels = monthly_data.map { |entry| month_label(entry[:month]) }
    revenue_values = monthly_data.map { |entry| (entry[:total_cents].to_f / 100).round(2) }
    order_counts = monthly_data.map { |entry| entry[:orders_count] }

    {
      type: 'bar',
      data: {
        labels: labels,
        datasets: [
          {
            type: 'line',
            label: "Chiffre d'affaires (€)",
            data: revenue_values,
            borderColor: '#2563eb',
            backgroundColor: 'rgba(37, 99, 235, 0.2)',
            tension: 0.3,
            yAxisID: 'y'
          },
          {
            type: 'bar',
            label: 'Commandes',
            data: order_counts,
            backgroundColor: 'rgba(59, 130, 246, 0.5)',
            yAxisID: 'y1'
          }
        ]
      },
      options: {
        responsive: true,
        interaction: { mode: 'index', intersect: false },
        stacked: false,
        scales: {
          y: {
            beginAtZero: true,
            title: { display: true, text: '€' }
          },
          y1: {
            beginAtZero: true,
            position: 'right',
            grid: { drawOnChartArea: false },
            title: { display: true, text: 'Commandes' }
          }
        }
      }
    }
  end

  def chart_config_json(config)
    ERB::Util.json_escape(config.to_json)
  end

  def weekday_label(weekday_number)
    labels = {
      0 => 'Dimanche',
      1 => 'Lundi',
      2 => 'Mardi',
      3 => 'Mercredi',
      4 => 'Jeudi',
      5 => 'Vendredi',
      6 => 'Samedi'
    }

    labels[weekday_number] || weekday_number.to_s
  end

  def month_label(date)
    I18n.l(date, format: '%B %Y')
  rescue I18n::ArgumentError
    date.strftime('%B %Y')
  end
end

