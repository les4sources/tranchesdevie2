import { Controller } from "@hotwired/stimulus"

// Page de connexion admin : affiche / masque le mot de passe, et garde le
// bouton « allumé » pendant l'envoi du formulaire.
export default class extends Controller {
  static targets = ["input", "eye"]

  toggle() {
    const shown = this.inputTarget.type === "text"
    this.inputTarget.type = shown ? "password" : "text"
    this.eyeTarget.setAttribute("aria-label", shown ? "Afficher le mot de passe" : "Masquer le mot de passe")
    this.eyeTarget.classList.toggle("is-on", !shown)
    this.inputTarget.focus()
  }

  submit() {
    this.element.classList.add("is-submitting")
  }
}
