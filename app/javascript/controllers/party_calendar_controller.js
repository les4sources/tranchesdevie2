import { Controller } from "@hotwired/stimulus"

// Calendrier de réservation Pizza party privée (#pizza-parties).
// Deux temps : choisir un JOUR dans la grille mensuelle, puis un CRÉNEAU
// (midi/soir) dans la carte de réservation. La valeur soumise reste le format
// serveur "YYYY-MM-DD|slot" (revalidé côté serveur à l'ajout panier).
export default class extends Controller {
  static targets = ["day", "input", "slotPanel", "slotLabel", "slotButton", "warning", "placeholder",
    "ovenHotNotice", "note", "noteCount"]

  connect() {
    this.countNote()
  }

  // Compteur de caractères du commentaire (#169). `maxlength` borne déjà la
  // saisie ; ceci ne fait que la rendre visible.
  countNote() {
    if (!this.hasNoteTarget || !this.hasNoteCountTarget) return
    this.noteCountTarget.textContent = this.noteTarget.value.length
  }

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

    // Les parties n'ont lieu que les jours de boulangerie (#201), donc le four
    // est toujours chaud — il n'y a plus de cas « four froid » à annoncer.
    this.toggleNotice(this.ovenHotNoticeTarget, day.dataset.ovenHot === "true")
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

  // Bloque la soumission tant que (date, créneau) n'est pas choisi, ou que le
  // commentaire est vide (#169). Déclaré AVANT cart#add sur le formulaire pour
  // pouvoir stopper la chaîne. Le serveur revalide les deux dans tous les cas.
  guard(event) {
    const missingSlot = !this.inputTarget.value
    const missingNote = this.hasNoteTarget && this.noteTarget.value.trim() === ""

    if (!missingSlot && !missingNote) return

    event.preventDefault()
    event.stopImmediatePropagation()

    this.warningTarget.textContent = missingSlot
      ? "Choisis une date et un créneau dans le calendrier pour réserver."
      : "Dis-nous un mot sur ton groupe avant de réserver."
    this.warningTarget.classList.remove("hidden")

    if (!missingSlot && missingNote) this.noteTarget.focus()
  }
}
