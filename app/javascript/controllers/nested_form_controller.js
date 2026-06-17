import { Controller } from "@hotwired/stimulus"

// Ajoute/supprime dynamiquement des lignes de formulaire imbriqué
// (utilisé pour les remises ciblées d'un groupe).
// Le <template data-nested-form-target="template"> contient une ligne modèle
// dont chaque "NEW_RECORD" est remplacé par un index unique.
export default class extends Controller {
  static targets = ["container", "template"]

  add(event) {
    event.preventDefault()
    const index = new Date().getTime()
    const html = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, index)
    this.containerTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-nested-form-target='row']")
    if (!row) return

    const destroyField = row.querySelector("input[name*='_destroy']")
    if (destroyField) {
      // Enregistrement existant : on le marque pour suppression et on le masque.
      destroyField.value = "1"
      row.style.display = "none"
    } else {
      // Nouvel enregistrement non persisté : on retire la ligne du DOM.
      row.remove()
    }
  }
}
