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

    const discountCents = this.computeDiscountCents(this.getSelectedCustomer())
    const totalCents = subtotalCents - discountCents

    if (this.hasTotalAmountTarget) {
      this.totalAmountTarget.textContent = this.formatCurrency(totalCents)
    }
  }

  // Réplique exacte de GroupDiscountService#total_discount_cents :
  // lignes ciblées (remise unitaire préchargée) + remise globale en % sur le
  // sous-total agrégé des lignes non ciblées (arrondi une seule fois).
  computeDiscountCents(customer) {
    if (!customer) return 0

    const targeted = customer.targeted_unit_discounts || {}
    const percent = customer.discount_percent || 0

    let targetedDiscount = 0
    let nonTargetedSubtotal = 0

    this.quantityTargets.forEach((input) => {
      const qty = parseInt(input.value, 10) || 0
      if (qty <= 0) return

      const variantId = input.dataset.variantId
      const priceCents = parseInt(input.dataset.priceCents, 10) || 0

      if (variantId && Object.prototype.hasOwnProperty.call(targeted, variantId)) {
        targetedDiscount += qty * (parseInt(targeted[variantId], 10) || 0)
      } else {
        nonTargetedSubtotal += qty * priceCents
      }
    })

    const percentDiscount = percent > 0 ? Math.round(nonTargetedSubtotal * percent / 100) : 0
    return targetedDiscount + percentDiscount
  }

  updateDiscountInfo() {
    const customer = this.getSelectedCustomer()
    const percent = customer?.discount_percent || 0
    const hasTargeted = customer && customer.targeted_unit_discounts &&
      Object.keys(customer.targeted_unit_discounts).length > 0

    if (customer && (percent > 0 || hasTargeted) && this.hasDiscountMessageTarget && this.hasDiscountTextTarget) {
      this.discountMessageTarget.classList.remove('hidden')
      this.discountTextTarget.textContent = hasTargeted
        ? "Ce montant tient compte des remises (globale et/ou ciblées) du client sélectionné."
        : `Ce montant tient compte d'une remise de ${percent}% appliquée au client sélectionné.`
    } else if (this.hasDiscountMessageTarget) {
      this.discountMessageTarget.classList.add('hidden')
    }
  }

  getSelectedCustomerId() {
    if (!this.hasCustomerSelectTarget) return null
    const value = this.customerSelectTarget.value
    return value ? parseInt(value, 10) : null
  }

  getSelectedCustomer() {
    const customerId = this.getSelectedCustomerId()
    if (!customerId || !this.customersValue) return null
    return this.customersValue.find(c => c.id === customerId) || null
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
