import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  print(event) {
    event.preventDefault()
    window.print()
  }

  copy(event) {
    event.preventDefault()
    const text = this.element.dataset.exportPayload
    if (!text) return

    navigator.clipboard
      .writeText(text)
      .then(() => {
        this.showToast("Données copiées dans le presse‑papiers")
      })
      .catch(() => {
        this.showToast("Impossible de copier les données", "error")
      })
  }

  showToast(message, kind = "info") {
    window.dispatchEvent(
      new CustomEvent("dashboard:toast", {
        detail: { message, kind }
      })
    )
  }
}


