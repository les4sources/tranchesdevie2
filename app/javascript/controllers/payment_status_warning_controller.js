import { Controller } from "@hotwired/stimulus"

// Garde-fou du select « Statut de paiement » (formulaire d'édition de commande) :
// sélectionner « Remboursé » ne rembourse rien — c'est une étiquette comptable.
// On affiche un avertissement dès que l'admin choisit « Remboursé » alors que la
// commande ne l'était pas déjà, pour pointer vers le vrai bouton « Rembourser ».
export default class extends Controller {
  static targets = ["select", "warning"]
  static values = { initial: String }

  connect() {
    this.toggle()
  }

  toggle() {
    const markedRefunded =
      this.selectTarget.value === "refunded" && this.initialValue !== "refunded"
    this.warningTarget.classList.toggle("hidden", !markedRefunded)
  }
}
