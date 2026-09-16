import { Controller } from "@hotwired/stimulus"

// Règlement d'une réservation de Pizza party déjà validée.
//
// Deux gestes liés : le client arrête son nombre de participants, PUIS paie. Le
// PaymentIntent n'est demandé au serveur qu'au clic sur le bouton — c'est lui
// qui fige le nombre côté commande et aligne le montant Stripe. Demander le PI
// au chargement laisserait le client payer un total qu'il vient de changer.
export default class extends Controller {
  static targets = [
    "persons", "countLabel", "patonsLabel", "totalLabel",
    "paymentElement", "submit", "submitLabel", "message"
  ]
  static values = { url: String, return: String, key: String, unit: Number, forfait: Number }

  connect() {
    this.stripe = null
    this.elements = null
    this.recalculate()
  }

  increment() {
    this.personsTarget.value = this.persons + 1
    this.recalculate()
  }

  decrement() {
    this.personsTarget.value = Math.max(1, this.persons - 1)
    this.recalculate()
  }

  get persons() {
    return Math.max(1, parseInt(this.personsTarget.value, 10) || 1)
  }

  // Aperçu côté client : le serveur reste seul juge du montant encaissé, mais le
  // client doit voir son total bouger quand il change le nombre.
  recalculate() {
    const patons = this.persons * this.unitValue
    const total = patons + this.forfaitValue

    this.countLabelTarget.textContent = this.persons
    this.patonsLabelTarget.textContent = this.format(patons)
    this.totalLabelTarget.textContent = this.format(total)
    this.submitLabelTarget.textContent = `Régler ${this.format(total)}`

    // Le nombre a changé après l'affichage du formulaire de carte : on le
    // démonte, il porte un montant périmé.
    if (this.elements) {
      this.paymentElementTarget.innerHTML = ""
      this.elements = null
      this.submitLabelTarget.textContent = `Confirmer et régler ${this.format(total)}`
    }
  }

  format(cents) {
    return (cents / 100).toFixed(2).replace(".", ",") + " €"
  }

  async submit() {
    this.submitTarget.disabled = true
    this.hideMessage()

    try {
      if (!this.elements) {
        const ready = await this.prepare()
        if (!ready) return
        this.submitLabelTarget.textContent = "Valider le paiement"
        this.submitTarget.disabled = false
        return
      }

      const { error } = await this.stripe.confirmPayment({
        elements: this.elements,
        confirmParams: { return_url: this.returnValue }
      })

      if (error) {
        this.showMessage(error.message || "Le paiement n'a pas abouti.")
        this.submitTarget.disabled = false
      }
    } catch (error) {
      this.showMessage("Connexion impossible, réessaie dans un instant.")
      this.submitTarget.disabled = false
    }
  }

  // Confirme le nombre côté serveur et monte le formulaire de paiement.
  async prepare() {
    const response = await fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({ persons: this.persons })
    })

    const data = await response.json()

    if (!data.success) {
      this.showMessage(data.error || "Impossible de préparer le paiement.")
      this.submitTarget.disabled = false
      return false
    }

    this.totalLabelTarget.textContent = data.total_label

    if (!this.stripe) this.stripe = Stripe(this.keyValue)
    this.elements = this.stripe.elements({ clientSecret: data.client_secret })
    this.elements.create("payment").mount(this.paymentElementTarget)
    return true
  }

  showMessage(text) {
    this.messageTarget.textContent = text
    this.messageTarget.classList.remove("hidden")
  }

  hideMessage() {
    this.messageTarget.classList.add("hidden")
  }
}
