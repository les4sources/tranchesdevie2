import { Controller } from "@hotwired/stimulus"

const SAVE_DELAY = 800

export default class extends Controller {
  static targets = ["form", "status"]
  static values = {
    url: String
  }

  connect() {
    this.timeout = null
    this.isSaving = false
  }

  queueSave() {
    this.setStatus("Modifications en attente", "adm-tone-warning")
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.save(), SAVE_DELAY)
  }

  save(event) {
    if (event) event.preventDefault()
    if (this.isSaving) return

    this.isSaving = true
    this.setStatus("Enregistrement…", "adm-tone-water")

    const formData = new FormData(this.formTarget)

    fetch(this.urlValue, {
      method: "PATCH",
      headers: { Accept: "application/json" },
      body: formData
    })
      .then((response) => {
        if (!response.ok) throw new Error("save_failed")
        return response.json()
      })
      .then(() => {
        this.setStatus("Note enregistrée", "adm-tone-success")
      })
      .catch(() => {
        this.setStatus("Erreur lors de l’enregistrement", "adm-tone-danger")
      })
      .finally(() => {
        this.isSaving = false
      })
  }

  // `toneClass` est une tonalité de l'admin (`adm-tone-*`), pas une couleur :
  // c'est `.adm-tonetext` qui va y chercher son `color`.
  setStatus(text, toneClass) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.className =
      "adm-tonetext text-xs font-medium transition-colors duration-200 " + toneClass
  }
}


