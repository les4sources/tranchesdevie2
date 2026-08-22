import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

export default class extends Controller {
  static values = {
    config: Object
  }

  connect() {
    this.renderChart()
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }

  renderChart() {
    if (!this.hasConfigValue) {
      return
    }

    const context = this.element.getContext("2d")
    this.chart = new Chart(context, this.configValue)
  }
}

