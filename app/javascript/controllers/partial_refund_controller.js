import { Controller } from "@hotwired/stimulus"

// Formulaire de remboursement partiel (fiche commande, admin).
//
// Le montant suit les quantités cochées — le boulanger coche « 1 froment aux
// graines » et lit tout de suite ce que ça rend. Il reste libre de le corriger
// (geste commercial, arrondi) : dès qu'il y touche, le calcul automatique
// s'efface et ne réécrit plus sa saisie.
export default class extends Controller {
  static targets = ["qty", "amount", "summary", "submit"]

  connect() {
    this.manual = false
    this.recalculate()
  }

  // Net de la ligne au prorata de la quantité cochée — même arrondi que
  // PartialRefundService.proposed_amount_cents côté serveur.
  lineCents(input) {
    const qty = parseInt(input.value || "0", 10)
    if (!qty || qty < 1) return 0

    const orderedQty = parseInt(input.dataset.orderedQty || "0", 10)
    const netFull = parseInt(input.dataset.netCents || "0", 10)
    if (!orderedQty) return 0

    return qty >= orderedQty ? netFull : Math.round((netFull * qty) / orderedQty)
  }

  recalculate() {
    const cents = this.qtyTargets.reduce((sum, input) => sum + this.lineCents(input), 0)
    const count = this.qtyTargets.reduce((sum, input) => sum + (parseInt(input.value || "0", 10) || 0), 0)

    if (this.hasSummaryTarget) {
      this.summaryTarget.textContent = count
        ? `${count} article${count > 1 ? "s" : ""} — ${this.euros(cents)}`
        : "Aucun article sélectionné"
    }

    if (!this.manual && this.hasAmountTarget) {
      this.amountTarget.value = cents ? (cents / 100).toFixed(2).replace(".", ",") : ""
    }

    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = count === 0
    }
  }

  markManual() {
    this.manual = true
  }

  euros(cents) {
    return `${(cents / 100).toFixed(2).replace(".", ",")} €`
  }
}
