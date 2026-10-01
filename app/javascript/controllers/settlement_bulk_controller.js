import { Controller } from "@hotwired/stimulus"

// Sélection groupée des commandes à pointer sur la fiche client.
//
// Chaque case porte le montant de sa commande (`data-amount-cents`) : le total
// dû de la sélection s'affiche au fil des coches — c'est le montant que le
// client doit régler, à lui annoncer avant le virement.
export default class extends Controller {
  static targets = ["checkbox", "selectAll", "action", "count", "total", "bar"]

  connect() {
    this.formatter = new Intl.NumberFormat("fr-BE", { style: "currency", currency: "EUR" })
    this.refresh()
  }

  toggleAll(event) {
    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = event.target.checked
    })
    this.refresh()
  }

  refresh() {
    const selected = this.checkboxTargets.filter((checkbox) => checkbox.checked)
    const totalCents = selected.reduce((sum, checkbox) => sum + Number(checkbox.dataset.amountCents || 0), 0)

    if (this.hasCountTarget) this.countTarget.textContent = selected.length
    if (this.hasTotalTarget) this.totalTarget.textContent = this.formatter.format(totalCents / 100)

    this.actionTargets.forEach((button) => {
      button.disabled = selected.length === 0
    })

    if (this.hasSelectAllTarget) {
      const all = this.checkboxTargets.length
      this.selectAllTarget.checked = all > 0 && selected.length === all
      this.selectAllTarget.indeterminate = selected.length > 0 && selected.length < all
    }
  }
}
