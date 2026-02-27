import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["amountBtn", "customAmount", "selectedAmount", "error", "submitBtn", "btnText", "btnSpinner"]
  static values = { createUrl: String }

  connect() {
    this.selectedAmountCents = 0
    this.bindAmountButtons()
  }

  bindAmountButtons() {
    this.amountBtnTargets.forEach(btn => {
      btn.addEventListener("click", () => this.selectAmount(parseInt(btn.dataset.amount)))
    })

    if (this.hasCustomAmountTarget) {
      this.customAmountTarget.addEventListener("input", (e) => {
        const euros = parseFloat(e.target.value) || 0
        this.selectAmount(Math.round(euros * 100))
      })
    }
  }

  selectAmount(amountCents) {
    this.selectedAmountCents = amountCents

    // Update UI
    this.amountBtnTargets.forEach(btn => {
      if (parseInt(btn.dataset.amount) === amountCents) {
        btn.classList.add("ring-2", "ring-green-500", "bg-green-50")
      } else {
        btn.classList.remove("ring-2", "ring-green-500", "bg-green-50")
      }
    })

    const euros = amountCents / 100
    const display = Number.isInteger(euros) ? `${euros} €` : `${euros.toFixed(2).replace('.', ',')} €`
    this.selectedAmountTarget.textContent = display
  }

  async submit() {
    if (this.selectedAmountCents < 500) {
      this.showError("Montant minimum: 5€")
      return
    }

    this.setLoading(true)
    this.hideError()

    try {
      // Create PaymentIntent
      const response = await fetch(this.createUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ amount_cents: this.selectedAmountCents })
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.error || "Erreur lors de la création du paiement")
      }

      // Redirect to Bancontact (server-side confirmed, just follow the redirect URL)
      window.location.href = data.redirect_url
    } catch (e) {
      this.showError(e.message)
      this.setLoading(false)
    }
  }

  showError(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.classList.remove("hidden")
    }
  }

  hideError() {
    if (this.hasErrorTarget) {
      this.errorTarget.classList.add("hidden")
    }
  }

  setLoading(loading) {
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = loading
    }
    if (this.hasBtnTextTarget) {
      this.btnTextTarget.classList.toggle("hidden", loading)
    }
    if (this.hasBtnSpinnerTarget) {
      this.btnSpinnerTarget.classList.toggle("hidden", !loading)
    }
  }
}
