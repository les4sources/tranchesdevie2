import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["quantity", "rowSubtotal", "totalAmount", "customerSelect", "discountInfo", "discountMessage", "discountText"]
  static values = {
    customers: Array
  }

  connect() {
    this.recalculate()
    this.updateDiscountInfo()
  }

  onCustomerChange() {
    this.updateDiscountInfo()
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

    let subtotalCents = 0

    this.rowSubtotalTargets.forEach((target) => {
      const productId = target.dataset.productId
      const cents = subtotalByProduct[productId] || 0
      subtotalCents += cents
      target.textContent = this.formatCurrency(cents)
    })

    // Calculer la remise si un client est sélectionné
    const selectedCustomerId = this.getSelectedCustomerId()
    const discountPercent = this.getDiscountPercent(selectedCustomerId)
    const discountCents = discountPercent > 0 
      ? Math.round(subtotalCents * discountPercent / 100)
      : 0
    const totalCents = subtotalCents - discountCents

    if (this.hasTotalAmountTarget) {
      this.totalAmountTarget.textContent = this.formatCurrency(totalCents)
    }
  }

  updateDiscountInfo() {
    const selectedCustomerId = this.getSelectedCustomerId()
    const discountPercent = this.getDiscountPercent(selectedCustomerId)

    if (discountPercent > 0 && this.hasDiscountMessageTarget && this.hasDiscountTextTarget) {
      this.discountMessageTarget.classList.remove('hidden')
      this.discountTextTarget.textContent = `Ce montant tient compte d'une remise de ${discountPercent}% appliquée au client sélectionné.`
    } else if (this.hasDiscountMessageTarget) {
      this.discountMessageTarget.classList.add('hidden')
    }
  }

  getSelectedCustomerId() {
    if (!this.hasCustomerSelectTarget) return null
    const value = this.customerSelectTarget.value
    return value ? parseInt(value, 10) : null
  }

  getDiscountPercent(customerId) {
    if (!customerId || !this.customersValue) return 0
    const customer = this.customersValue.find(c => c.id === customerId)
    return customer?.discount_percent || 0
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

