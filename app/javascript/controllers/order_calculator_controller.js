import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["quantity", "rowSubtotal", "totalAmount"]

  connect() {
    this.recalculate()
  }

  recalculate() {
    const subtotalByProduct = {}

    this.quantityTargets.forEach((input) => {
      const qty = parseInt(input.value, 10) || 0
      const priceCents = parseInt(input.dataset.priceCents, 10) || 0
      const productId = input.dataset.productId

      if (!productId) return

      if (!subtotalByProduct[productId]) {
        subtotalByProduct[productId] = 0
      }

      subtotalByProduct[productId] += qty * priceCents
    })

    let totalCents = 0

    this.rowSubtotalTargets.forEach((target) => {
      const productId = target.dataset.productId
      const cents = subtotalByProduct[productId] || 0
      totalCents += cents
      target.textContent = this.formatCurrency(cents)
    })

    if (this.hasTotalAmountTarget) {
      this.totalAmountTarget.textContent = this.formatCurrency(totalCents)
    }
  }

  resetQuantities(event) {
    event.preventDefault()
    this.quantityTargets.forEach((input) => {
      input.value = 0
    })
    this.recalculate()
  }

  formatCurrency(cents) {
    const euros = (cents || 0) / 100
    return this.currencyFormatter.format(euros)
  }

  get currencyFormatter() {
    if (!this._currencyFormatter) {
      this._currencyFormatter = new Intl.NumberFormat("fr-FR", {
        style: "currency",
        currency: "EUR",
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
      })
    }
    return this._currencyFormatter
  }
}

