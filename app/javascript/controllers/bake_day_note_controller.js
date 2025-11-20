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
    this.setStatus("Modifications en attente", "text-amber-600")
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.save(), SAVE_DELAY)
  }

  save(event) {
    if (event) event.preventDefault()
    if (this.isSaving) return

    this.isSaving = true
    this.setStatus("Enregistrement…", "text-blue-600")

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
        this.setStatus("Note enregistrée", "text-emerald-600")
      })
      .catch(() => {
        this.setStatus("Erreur lors de l’enregistrement", "text-red-600")
      })
      .finally(() => {
        this.isSaving = false
      })
  }

  setStatus(text, statusClass) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.className =
      "text-xs font-medium transition-colors duration-200 " + statusClass
  }
}


