import { Controller } from "@hotwired/stimulus"

// Sélection groupée des commandes sur l'écran Facturation (#retour Manon).
//
// Une seule form couvre tous les clients de l'écran. Chaque case porte le
// `data-group` de son client : la case « tout sélectionner » d'un client ne
// coche donc que ses propres lignes, et son état (coché / indéterminé) suit ce
// que l'utilisateur coche à la main.
export default class extends Controller {
  static targets = ["checkbox", "selectAll", "action", "count"]

  connect() {
    this.refresh()
  }

  toggleAll(event) {
    const group = event.target.dataset.group
    this.checkboxesFor(group).forEach((checkbox) => {
      checkbox.checked = event.target.checked
    })
    this.refresh()
  }

  refresh() {
    const selected = this.checkboxTargets.filter((checkbox) => checkbox.checked)

    if (this.hasCountTarget) {
      this.countTarget.textContent = selected.length
    }

    this.actionTargets.forEach((button) => {
      button.disabled = selected.length === 0
    })

    this.selectAllTargets.forEach((master) => {
      const group = this.checkboxesFor(master.dataset.group)
      const checked = group.filter((checkbox) => checkbox.checked).length
      master.checked = group.length > 0 && checked === group.length
      master.indeterminate = checked > 0 && checked < group.length
    })
  }

  checkboxesFor(group) {
    return this.checkboxTargets.filter((checkbox) => checkbox.dataset.group === group)
  }
}
