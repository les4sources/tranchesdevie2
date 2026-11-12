import { Controller } from "@hotwired/stimulus"

// Bulle de détail d'une case du suivi de facturation (#retour Michael).
//
// Deux façons de l'ouvrir :
//   - au survol de la souris : la bulle s'ouvre après un court délai et se
//     referme quand la souris quitte la case ET la bulle (on peut y entrer pour
//     suivre un lien) ;
//   - au clic : la bulle s'épingle et reste ouverte jusqu'à un clic ailleurs
//     ou Échap.
//
// Ouverture et fermeture reposent sur l'API `popover` native du navigateur
// (`popovertarget` sur le bouton) : une seule bulle ouverte à la fois, et le
// clic fonctionne même si ce contrôleur ne se charge pas. Le contrôleur place
// la bulle sous la case, en position fixe — elle échappe ainsi au défilement
// horizontal du tableau.
//
// Le survol ne réagit qu'à une vraie souris (`pointerType === "mouse"`) : sur
// tablette, un toucher déclencherait sinon une ouverture « survol » aussitôt
// refermée par le clic qui suit.
const SHOW_DELAY_MS = 250
const HIDE_DELAY_MS = 200

export default class extends Controller {
  static targets = ["trigger", "popover"]

  connect() {
    this.pinned = false
    this.showTimer = null
    this.hideTimer = null

    this.boundToggle = this.onToggle.bind(this)
    this.boundClose = this.close.bind(this)
    this.boundEnter = this.onPointerEnter.bind(this)
    this.boundLeave = this.onPointerLeave.bind(this)
    this.boundClick = this.onClick.bind(this)

    this.popoverTarget.addEventListener("toggle", this.boundToggle)
    this.triggerTarget.addEventListener("click", this.boundClick)
    for (const element of [this.triggerTarget, this.popoverTarget]) {
      element.addEventListener("pointerenter", this.boundEnter)
      element.addEventListener("pointerleave", this.boundLeave)
    }
  }

  disconnect() {
    this.popoverTarget.removeEventListener("toggle", this.boundToggle)
    this.triggerTarget.removeEventListener("click", this.boundClick)
    for (const element of [this.triggerTarget, this.popoverTarget]) {
      element.removeEventListener("pointerenter", this.boundEnter)
      element.removeEventListener("pointerleave", this.boundLeave)
    }
    this.clearTimers()
    this.stopListening()
  }

  onPointerEnter(event) {
    if (event.pointerType !== "mouse") return

    clearTimeout(this.hideTimer)
    if (this.isOpen()) return

    clearTimeout(this.showTimer)
    this.showTimer = setTimeout(() => this.open(), SHOW_DELAY_MS)
  }

  onPointerLeave(event) {
    if (event.pointerType !== "mouse") return

    clearTimeout(this.showTimer)
    if (this.pinned) return

    clearTimeout(this.hideTimer)
    this.hideTimer = setTimeout(() => this.close(), HIDE_DELAY_MS)
  }

  // Un clic sur une bulle ouverte au survol l'épingle au lieu de la refermer :
  // on empêche alors la bascule native de `popovertarget`.
  onClick(event) {
    clearTimeout(this.showTimer)
    clearTimeout(this.hideTimer)

    if (this.isOpen() && !this.pinned) {
      event.preventDefault()
      this.pinned = true
    } else if (!this.isOpen()) {
      this.pinned = true
    }
  }

  onToggle(event) {
    if (event.newState === "open") {
      this.position()
      window.addEventListener("scroll", this.boundClose, { passive: true, capture: true })
      window.addEventListener("resize", this.boundClose)
    } else {
      this.pinned = false
      this.clearTimers()
      this.stopListening()
    }
  }

  open() {
    if (!this.isOpen()) this.popoverTarget.showPopover()
  }

  close() {
    if (this.isOpen()) this.popoverTarget.hidePopover()
  }

  isOpen() {
    return this.popoverTarget.matches(":popover-open")
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

    // Collée à la case (4 px) : la souris passe de l'une à l'autre sans
    // traverser un vide qui refermerait la bulle.
    let top = trigger.bottom + 4
    if (top + height > window.innerHeight - margin && trigger.top - height - 4 > margin) {
      top = trigger.top - height - 4
    }

    // Sans ce contrôleur, la bulle garde le centrage natif du navigateur.
    popover.style.position = "fixed"
    popover.style.inset = "auto"
    popover.style.margin = "0"
    popover.style.left = `${left}px`
    popover.style.top = `${top}px`
  }

  clearTimers() {
    clearTimeout(this.showTimer)
    clearTimeout(this.hideTimer)
  }

  stopListening() {
    window.removeEventListener("scroll", this.boundClose, { capture: true })
    window.removeEventListener("resize", this.boundClose)
  }
}
