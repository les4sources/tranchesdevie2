import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "quantity", "rowSubtotal", "totalAmount", "customerSelect",
    "discountInfo", "discountMessage", "discountText",
    "finalTotal", "mismatch", "mismatchText"
  ]
  static values = {
    customers: Array
  }

  connect() {
    // Le montant final est-il déjà désaligné du calcul à l'ouverture ? Si oui,
    // c'est une saisie manuelle (prix négocié) — ou la dérive qu'on veut rendre
    // visible : on ne l'écrase pas, on l'annonce.
    this.manualTotal = this.hasFinalTotalTarget &&
      this.finalTotalTarget.value !== "" &&
      this.centsFromInput() !== this.computeTotalCents()

    this.recalculate()
    this.updateDiscountInfo()
  }

  // L'admin a repris la main sur le montant final : on cesse de le synchroniser.
  onFinalTotalInput() {
    this.manualTotal = true
    this.updateMismatch(this.computeTotalCents())
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

    this.syncFinalTotal(totalCents)
  }

  // Le montant final suit les quantités tant que l'admin ne l'a pas saisi à la
  // main. C'est ce qui empêche une commande d'être enregistrée à 90 € alors que
  // ses lignes en font 81 (#retour Manon) — le relevé PDF affichait alors un
  // sous-total qui ne correspondait plus à son propre détail.
  syncFinalTotal(totalCents) {
    if (!this.hasFinalTotalTarget) return

    if (!this.manualTotal) {
      this.finalTotalTarget.value = (totalCents / 100).toFixed(2)
    }

    this.updateMismatch(totalCents)
  }

  // Écart entre le montant saisi et le montant calculé — jamais bloquant (un
  // prix négocié est légitime), mais jamais silencieux non plus.
  updateMismatch(totalCents) {
    if (!this.hasMismatchTarget || !this.hasFinalTotalTarget) return

    const enteredCents = this.centsFromInput()
    const deltaCents = enteredCents === null ? 0 : enteredCents - totalCents

    if (deltaCents === 0) {
      this.mismatchTarget.classList.add("hidden")
      return
    }

    const sign = deltaCents > 0 ? "+" : "-"
    this.mismatchTarget.classList.remove("hidden")
    this.mismatchTextTarget.textContent =
      `Montant saisi à la main : écart de ${sign}${this.formatCurrency(Math.abs(deltaCents))} ` +
      `par rapport au calcul (${this.formatCurrency(totalCents)}).`
  }

  // Montant du champ « Montant final », en cents. null si le champ est vide.
  centsFromInput() {
    if (!this.hasFinalTotalTarget) return null

    const raw = this.finalTotalTarget.value
    if (raw === "" || raw === null) return null

    const value = parseFloat(String(raw).replace(",", "."))
    return Number.isNaN(value) ? null : Math.round(value * 100)
  }

  // Total calculé depuis les quantités et la remise du client sélectionné.
  computeTotalCents() {
    const subtotalCents = this.quantityTargets.reduce((sum, input) => {
      const qty = parseInt(input.value, 10) || 0
      const priceCents = parseInt(input.dataset.priceCents, 10) || 0
      return sum + qty * priceCents
    }, 0)

    return subtotalCents - this.computeDiscountCents(this.getSelectedCustomer())
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
