import { Controller } from "@hotwired/stimulus"

// Vérification du numéro sur le formulaire de DEMANDE de Pizza party.
//
// Réutilise les endpoints OTP du checkout (/checkout/verify_phone et
// /checkout/verify_otp), qui ne touchent que la session — aucune modification
// côté serveur. La différence avec checkout_controller : on NE RECHARGE PAS la
// page au succès. Le client a déjà choisi sa date, saisi son nombre de
// participants et écrit son commentaire ; un reload lui ferait tout reperdre.
export default class extends Controller {
  static targets = ["phone", "code", "codeSection", "message", "verified", "submit", "identity"]

  async sendCode(event) {
    event.preventDefault()

    const phone = this.phoneTarget.value.trim()
    if (!phone) {
      this.show("Entre ton numéro de GSM pour recevoir le code.", "error")
      return
    }

    const response = await this.post("/checkout/verify_phone", { phone_e164: phone })
    if (!response) return

    if (response.success) {
      this.codeSectionTarget.classList.remove("hidden")
      this.codeTarget.focus()
      this.show(response.message || "Code envoyé par SMS.", "success")
    } else {
      this.show(response.error || "Envoi impossible.", "error")
    }
  }

  async verify(event) {
    event.preventDefault()

    const code = this.codeTarget.value.trim()
    if (code.length !== 6) {
      this.show("Le code compte 6 chiffres.", "error")
      return
    }

    const identity = this.identityValues()
    const response = await this.post("/checkout/verify_otp", { code, ...identity })
    if (!response) return

    if (response.success) {
      this.verifiedTarget.value = "1"
      this.codeSectionTarget.classList.add("hidden")
      this.submitTarget.disabled = false
      this.show("Numéro vérifié. Tu peux envoyer ta demande.", "success")
    } else {
      this.show(response.error || "Code incorrect.", "error")
    }
  }

  identityValues() {
    const values = {}
    this.identityTargets.forEach((field) => {
      values[field.dataset.identityKey] = field.value.trim()
    })
    return values
  }

  async post(url, body) {
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify(body)
      })
      return await response.json()
    } catch (error) {
      this.show("Connexion impossible, réessaie dans un instant.", "error")
      return null
    }
  }

  show(message, type) {
    this.messageTarget.textContent = message
    this.messageTarget.className =
      type === "success"
        ? "mt-3 text-sm font-medium text-sage-700"
        : "mt-3 text-sm font-medium text-danger-700"
    this.messageTarget.classList.remove("hidden")
  }
}
