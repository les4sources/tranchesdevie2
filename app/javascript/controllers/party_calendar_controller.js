import { Controller } from "@hotwired/stimulus"

// Calendrier de réservation Pizza party privée (#pizza-parties).
// Deux temps : choisir un JOUR dans la grille mensuelle, puis un CRÉNEAU
// (midi/soir) dans la carte de réservation. La valeur soumise reste le format
// serveur "YYYY-MM-DD|slot" (revalidé côté serveur à l'ajout panier).
export default class extends Controller {
  static targets = ["day", "input", "slotPanel", "slotLabel", "slotButton", "warning", "placeholder",
    "ovenHotNotice", "ovenColdNotice"]

  selectDay(event) {
    const day = event.currentTarget

    this.dayTargets.forEach((el) => el.setAttribute("aria-pressed", el === day ? "true" : "false"))
    this.date = day.dataset.date
    this.inputTarget.value = ""

    this.slotButtonTargets.forEach((button) => {
      button.disabled = day.dataset[button.dataset.slot] !== "true"
      button.setAttribute("aria-pressed", "false")
    })

    this.slotLabelTarget.textContent = day.dataset.label
    this.placeholderTarget.classList.add("hidden")
    this.slotPanelTarget.classList.remove("hidden")
    this.warningTarget.classList.add("hidden")

    // Info chauffe : four déjà chaud les jours de boulangerie, sinon ~3 h de
    // chauffe gérées par le groupe.
    this.toggleNotice(this.ovenHotNoticeTarget, day.dataset.ovenHot === "true")
    this.toggleNotice(this.ovenColdNoticeTarget, day.dataset.ovenHot !== "true")
  }

  toggleNotice(el, show) {
    el.classList.toggle("hidden", !show)
    el.classList.toggle("flex", show)
  }

  selectSlot(event) {
    const button = event.currentTarget

    this.slotButtonTargets.forEach((el) => el.setAttribute("aria-pressed", el === button ? "true" : "false"))
    this.inputTarget.value = `${this.date}|${button.dataset.slot}`
    this.warningTarget.classList.add("hidden")
  }

  // Bloque la soumission tant que (date, créneau) n'est pas choisi. Déclaré
  // AVANT cart#add sur le formulaire pour pouvoir stopper la chaîne.
  guard(event) {
    if (this.inputTarget.value) return

    event.preventDefault()
    event.stopImmediatePropagation()
    this.warningTarget.classList.remove("hidden")
  }
}
