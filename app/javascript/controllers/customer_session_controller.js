import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["identifierInput", "otpInput", "channelHint", "firstNameInput", "lastNameInput"]

  // Detects whether the typed identifier looks like an email or a phone number.
  looksLikeEmail(value) {
    return (value || "").includes("@")
  }

  // Live hint under the field so the customer knows which channel will be used.
  updateChannelHint() {
    if (!this.hasChannelHintTarget) return

    const value = (this.identifierInputTarget.value || "").trim()
    if (value === "") {
      this.channelHintTarget.textContent = ""
    } else if (this.looksLikeEmail(value)) {
      this.channelHintTarget.textContent = "✉️ On t'enverra le code par e-mail"
    } else {
      this.channelHintTarget.textContent = "📱 On t'enverra le code par SMS"
    }
  }

  async sendCode(event) {
    event.preventDefault()

    const identifier = this.identifierInputTarget?.value?.trim()
    if (!identifier) {
      this.showMessage("Entre ton numéro de GSM ou ton e-mail", "error")
      return
    }

    const button = event.currentTarget
    const originalText = button.textContent
    button.disabled = true
    button.textContent = "Envoi…"

    try {
      const formData = new FormData()
      formData.append("identifier", identifier)

      const response = await fetch("/connexion", {
        method: "POST",
        headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content },
        body: formData
      })

      const html = await response.text()
      const doc = new DOMParser().parseFromString(html, "text/html")
      const alertElement = doc.querySelector(".alert, [class*='alert'], .bg-danger-100")

      if (!response.ok || alertElement) {
        this.showMessage(alertElement ? alertElement.textContent.trim() : "Erreur lors de l'envoi du code", "error")
        return
      }

      const otpSection = document.getElementById("otp-input-section")
      if (otpSection) otpSection.classList.remove("hidden")
      this.otpInputTarget?.focus()

      const noticeElement = doc.querySelector(".notice, [class*='notice'], .bg-sage-100")
      this.showMessage(noticeElement ? noticeElement.textContent.trim() : "Code envoyé", "success")
    } catch (error) {
      this.showMessage("Erreur de connexion", "error")
    } finally {
      button.disabled = false
      button.textContent = originalText
    }
  }

  async verifyOTP(event) {
    event.preventDefault()

    const code = this.otpInputTarget?.value
    if (!code || code.length !== 6) {
      this.showMessage("Entre le code à 6 chiffres", "error")
      return
    }

    const button = event.currentTarget
    button.disabled = true
    button.textContent = "Vérification…"

    try {
      const formData = new FormData()
      formData.append("identifier", this.identifierInputTarget.value.trim())
      formData.append("otp_code", code)

      const response = await fetch("/connexion", {
        method: "POST",
        headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content },
        body: formData
      })

      if (response.redirected) {
        window.location.href = response.url
        return
      }

      const html = await response.text()
      const doc = new DOMParser().parseFromString(html, "text/html")

      // Identifiant inconnu : le code est validé, il faut maintenant le prénom.
      if (doc.getElementById("needs-name-marker")) {
        document.getElementById("credentials-step")?.classList.add("hidden")
        document.getElementById("name-step")?.classList.remove("hidden")
        this.firstNameInputTarget?.focus()
        return
      }

      const alertElement = doc.querySelector(".alert, [class*='alert'], .bg-danger-100")
      this.showMessage(alertElement ? alertElement.textContent.trim() : "Erreur lors de la vérification", "error")
    } catch (error) {
      this.showMessage("Erreur de connexion", "error")
    } finally {
      button.disabled = false
      button.textContent = "Vérifier le code"
    }
  }

  // Étape 3 : crée le compte pour un nouvel identifiant (OTP déjà validé côté serveur).
  async completeSignup(event) {
    event.preventDefault()

    const firstName = this.firstNameInputTarget?.value?.trim()
    if (!firstName) {
      this.showNameMessage("Entre ton prénom", "error")
      return
    }

    const button = event.currentTarget
    button.disabled = true
    button.textContent = "Création…"

    try {
      const formData = new FormData()
      formData.append("complete_signup", "1")
      formData.append("first_name", firstName)
      formData.append("last_name", this.lastNameInputTarget?.value?.trim() || "")

      const response = await fetch("/connexion", {
        method: "POST",
        headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content },
        body: formData
      })

      if (response.redirected) {
        window.location.href = response.url
        return
      }

      const html = await response.text()
      const doc = new DOMParser().parseFromString(html, "text/html")
      const alertElement = doc.querySelector(".alert, [class*='alert'], .bg-danger-100")
      this.showNameMessage(alertElement ? alertElement.textContent.trim() : "Erreur lors de la création du compte", "error")
    } catch (error) {
      this.showNameMessage("Erreur de connexion", "error")
    } finally {
      button.disabled = false
      button.textContent = "Créer mon compte"
    }
  }

  showNameMessage(message, type) {
    const messageEl = document.getElementById("name-message")
    if (messageEl) {
      messageEl.textContent = message
      messageEl.className = type === "success" ? "mt-4 text-sm text-sage-700" : "mt-4 text-sm text-danger-700"
      messageEl.classList.remove("hidden")
    }
  }

  showMessage(message, type) {
    const messageEl = document.getElementById("otp-message")
    if (messageEl) {
      messageEl.textContent = message
      messageEl.className = type === "success" ? "mt-4 text-sm text-sage-700" : "mt-4 text-sm text-danger-700"
      messageEl.classList.remove("hidden")
    }
  }
}
