import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["amountBtn", "customAmount", "selectedAmount", "error", "submitBtn", "btnText", "btnSpinner"]
  static values = { createUrl: String, successUrl: String }

  connect() {
    this.selectedAmountCents = 0
    this.stripe = null
    this.elements = null

    this.initStripe()
    this.bindAmountButtons()
  }

  async initStripe() {
    const stripeKey = document.querySelector('meta[name="stripe-key"]')?.content
    if (!stripeKey) {
      console.error("Stripe public key not found")
      return
    }

    this.stripe = Stripe(stripeKey)
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

      // Redirect to Bancontact (using "if_required" to handle redirect manually and avoid new window)
      const { error, paymentIntent } = await this.stripe.confirmBancontactPayment(data.client_secret, {
        payment_method: {
          billing_details: {
            name: "Client"
          }
        },
        return_url: this.successUrlValue
      }, {
        handleActions: false
      })

      if (error) {
        throw new Error(error.message)
      }

      if (paymentIntent.status === "requires_action" && paymentIntent.next_action) {
        window.location.href = paymentIntent.next_action.redirect_to_url.url
      } else {
        window.location.href = this.successUrlValue + "?payment_intent=" + paymentIntent.id
      }
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
