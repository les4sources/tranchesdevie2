import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "overlay", "recipient", "date", "subject", "body", "error", "resendButton"]

  open(event) {
    event.preventDefault()
    event.stopPropagation()

    this.resendUrl = event.currentTarget.dataset.resendUrl
    const showUrl = event.currentTarget.dataset.showUrl

    this.hideError()
    this.openModal()

    fetch(showUrl, { headers: { "Accept": "application/json" } })
      .then((response) => response.json())
      .then((data) => {
        this.recipientTarget.textContent = data.to_email || ""
        this.dateTarget.textContent = data.sent_at || ""
        this.subjectTarget.textContent = data.subject || "(sans objet)"
        this.bodyTarget.srcdoc = data.body_html || ""
      })
      .catch(() => this.showError("Impossible de charger l'e-mail"))
  }

  async resend(event) {
    event.preventDefault()
    if (!this.resendUrl) return

    const button = this.resendButtonTarget
    const originalText = button.textContent
    button.disabled = true
    button.textContent = "Envoi…"

    try {
      const response = await fetch(this.resendUrl, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "application/json"
        }
      })
      const data = await response.json()

      if (data.success) {
        this.close()
        window.location.reload()
      } else {
        this.showError(data.error || "Erreur lors du renvoi de l'e-mail")
        button.disabled = false
        button.textContent = originalText
      }
    } catch (error) {
      this.showError("Erreur de connexion")
      button.disabled = false
      button.textContent = originalText
    }
  }

  openModal() {
    this.modalTarget.classList.remove("hidden")
    document.body.style.overflow = "hidden"
  }

  close() {
    this.modalTarget.classList.add("hidden")
    document.body.style.overflow = ""
  }

  closeBackground(event) {
    if (event.target === this.overlayTarget) {
      this.close()
    }
  }

  closeWithEscape(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }

  showError(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.querySelector("p").textContent = message
      this.errorTarget.classList.remove("hidden")
    }
  }

  hideError() {
    if (this.hasErrorTarget) {
      this.errorTarget.classList.add("hidden")
    }
  }
}
