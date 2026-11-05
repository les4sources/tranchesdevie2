import { Controller } from "@hotwired/stimulus"

// Bulle de détail d'une case du suivi de facturation (#retour Michael).
//
// Ouverture et fermeture sont confiées à l'API `popover` native du navigateur
// (`popovertarget` sur le bouton) : clic pour ouvrir, clic ailleurs ou Échap
// pour refermer, une seule bulle ouverte à la fois. Ce contrôleur ne fait que
// placer la bulle sous la case cliquée, en position fixe — elle échappe ainsi
// au défilement horizontal du tableau.
export default class extends Controller {
  static targets = ["trigger", "popover"]

  connect() {
    this.boundToggle = this.onToggle.bind(this)
    this.boundClose = this.close.bind(this)
    this.popoverTarget.addEventListener("toggle", this.boundToggle)
  }

  disconnect() {
    this.popoverTarget.removeEventListener("toggle", this.boundToggle)
    this.stopListening()
  }

  onToggle(event) {
    if (event.newState === "open") {
      this.position()
      window.addEventListener("scroll", this.boundClose, { passive: true, capture: true })
      window.addEventListener("resize", this.boundClose)
    } else {
      this.stopListening()
    }
  }

  // Sous la case, alignée sur son bord gauche ; repliée vers la gauche ou
  // au-dessus quand la place manque.
  position() {
    const margin = 8
    const trigger = this.triggerTarget.getBoundingClientRect()
    const popover = this.popoverTarget
    const width = popover.offsetWidth
    const height = popover.offsetHeight

    let left = trigger.left
    if (left + width > window.innerWidth - margin) left = window.innerWidth - margin - width
    left = Math.max(margin, left)

    let top = trigger.bottom + 6
    if (top + height > window.innerHeight - margin && trigger.top - height - 6 > margin) {
      top = trigger.top - height - 6
    }

    // Sans ce contrôleur, la bulle garde le centrage natif du navigateur.
    popover.style.position = "fixed"
    popover.style.inset = "auto"
    popover.style.margin = "0"
    popover.style.left = `${left}px`
    popover.style.top = `${top}px`
  }

  close() {
    if (this.popoverTarget.matches(":popover-open")) this.popoverTarget.hidePopover()
  }

  stopListening() {
    window.removeEventListener("scroll", this.boundClose, { capture: true })
    window.removeEventListener("resize", this.boundClose)
  }
}
