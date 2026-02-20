import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["quantity", "rowSubtotal", "totalAmount", "customerSelect", "discountInfo", "discountMessage", "discountText", "productCard", "variantRow"]
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
      target.textContent = cents > 0 ? this.formatCurrency(cents) : ""
      // Update subtotal color
      if (cents > 0) {
        target.classList.remove("text-gray-400")
        target.classList.add("text-indigo-600")
      } else {
        target.classList.remove("text-indigo-600")
        target.classList.add("text-gray-400")
      }
    })

    // Update card borders
    this.productCardTargets.forEach((card) => {
      const productId = card.dataset.productId
      const hasSelection = (subtotalByProduct[productId] || 0) > 0
      if (hasSelection) {
        card.classList.remove("border-gray-200", "shadow-sm")
        card.classList.add("border-indigo-400", "shadow-md", "ring-1", "ring-indigo-100")
      } else {
        card.classList.remove("border-indigo-400", "shadow-md", "ring-1", "ring-indigo-100")
        card.classList.add("border-gray-200", "shadow-sm")
      }
    })

    // Update variant row styles
    this.quantityTargets.forEach((input) => {
      const qty = parseInt(input.value, 10) || 0
      const variantId = input.dataset.variantId
      const row = this.variantRowTargets.find(r => r.dataset.variantId === variantId)
      if (row) {
        if (qty > 0) {
          row.classList.remove("bg-gray-50")
          row.classList.add("bg-indigo-50")
          input.classList.remove("text-gray-400")
          input.classList.add("text-indigo-700")
        } else {
          row.classList.remove("bg-indigo-50")
          row.classList.add("bg-gray-50")
          input.classList.remove("text-indigo-700")
          input.classList.add("text-gray-400")
        }
      }
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

  increment(event) {
    event.preventDefault()
    const variantId = event.currentTarget.dataset.variantId
    const input = this.quantityTargets.find(i => i.dataset.variantId === variantId)
    if (input) {
      input.value = (parseInt(input.value, 10) || 0) + 1
      this.recalculate()
    }
  }

  decrement(event) {
    event.preventDefault()
    const variantId = event.currentTarget.dataset.variantId
    const input = this.quantityTargets.find(i => i.dataset.variantId === variantId)
    if (input) {
      const current = parseInt(input.value, 10) || 0
      input.value = Math.max(0, current - 1)
      this.recalculate()
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

