import { Controller } from "@hotwired/stimulus"

// Garde délibérée avant annulation d'une fournée (#133).
// Le bouton de confirmation reste désactivé tant que l'admin n'a pas retapé
// EXACTEMENT la date attendue (JJ/MM/AAAA) dans le champ de garde.
export default class extends Controller {
  static targets = ["input", "submit"]
  static values = { expected: String }

  connect() {
    this.validate()
  }

  validate() {
    const typed = this.inputTarget.value.trim()
    this.submitTarget.disabled = typed !== this.expectedValue
  }
}
