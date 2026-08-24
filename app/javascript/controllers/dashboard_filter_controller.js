import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row"]
  static values = {
    filter: { type: String, default: "all" }
  }

  change(event) {
    this.filterValue = event.currentTarget.dataset.filter
    this.updateButtons(event.currentTarget)
    this.applyFilter()
  }

  applyFilter() {
    this.rowTargets.forEach((row) => {
      const category = row.dataset.category
      row.classList.toggle(
        "hidden",
        this.filterValue !== "all" && this.filterValue !== category
      )
    })
  }

  updateButtons(activeButton) {
    const buttons = activeButton
      .closest("[data-filter-group]")
      ?.querySelectorAll("button")

    buttons?.forEach((button) => {
      // Même principe que les onglets : `.adm-filter-active` porte l'apparence,
      // le contrôleur ne connaît qu'un état actif / inactif.
      button.classList.toggle("adm-filter-active", button === activeButton)
    })
  }
}


