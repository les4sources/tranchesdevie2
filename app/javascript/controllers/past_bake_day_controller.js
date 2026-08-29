import { Controller } from "@hotwired/stimulus"

// Régularisation d'un jour passé (#198). Encoder une vente après coup est
// légitime — c'est le point de l'issue — mais ça ne doit jamais se faire sans
// s'en rendre compte : l'avertissement apparaît au choix du jour, pas après
// l'enregistrement.
export default class extends Controller {
  static targets = ["select", "warning"]
  static values = {
    pastIds: Array
  }

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasWarningTarget || !this.hasSelectTarget) return

    const selected = parseInt(this.selectTarget.value, 10)
    const isPast = Number.isInteger(selected) && this.pastIdsValue.includes(selected)

    this.warningTarget.classList.toggle("hidden", !isPast)
  }
}
