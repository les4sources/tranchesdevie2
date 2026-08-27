import { Controller } from "@hotwired/stimulus"

// Bulle en position fixe : elle échappe au `overflow` du tableau qui la
// contiendrait autrement.
//
// Deux modes d'ouverture : au survol, et au toucher. Une bulle qui ne s'ouvre
// qu'au survol est inaccessible sur téléphone — et c'est là que le détail du
// calcul sert le plus, devant le pétrin.
//
// Le mode tactile ne se déduit pas d'un `matchMedia` — un portable à écran
// tactile répond « oui » aux deux — mais du premier `touchstart` réel. Ce
// premier contact démonte les écouteurs de survol : le navigateur synthétise
// un `mouseenter` après chaque tap, qui rouvrirait aussitôt la bulle qu'on
// vient de refermer.
export default class extends Controller {
  static targets = ["trigger", "popover"]

  connect() {
    this.hideTimeout = null
    this.touchMode = false

    this.boundShow = this.show.bind(this)
    this.boundHide = this.scheduleHide.bind(this)
    this.boundCancelHide = this.cancelHide.bind(this)
    this.boundEnterTouchMode = this.enterTouchMode.bind(this)
    this.boundToggle = this.toggle.bind(this)
    this.boundDismiss = this.dismiss.bind(this)

    this.attachHover()
    // `passive` : on ne bloque jamais le démarrage d'un défilement au doigt,
    // le déclencheur vit dans un tableau qui se fait glisser.
    this.triggerTarget.addEventListener("touchstart", this.boundEnterTouchMode, { passive: true })
    this.triggerTarget.addEventListener("click", this.boundToggle)
    document.addEventListener("click", this.boundDismiss)
  }

  disconnect() {
    this.detachHover()
    this.triggerTarget.removeEventListener("touchstart", this.boundEnterTouchMode)
    this.triggerTarget.removeEventListener("click", this.boundToggle)
    document.removeEventListener("click", this.boundDismiss)
    if (this.hideTimeout) clearTimeout(this.hideTimeout)
  }

  attachHover() {
    this.triggerTarget.addEventListener("mouseenter", this.boundShow)
    this.triggerTarget.addEventListener("mouseleave", this.boundHide)
    this.popoverTarget.addEventListener("mouseenter", this.boundCancelHide)
    this.popoverTarget.addEventListener("mouseleave", this.boundHide)
  }

  detachHover() {
    this.triggerTarget.removeEventListener("mouseenter", this.boundShow)
    this.triggerTarget.removeEventListener("mouseleave", this.boundHide)
    this.popoverTarget.removeEventListener("mouseenter", this.boundCancelHide)
    this.popoverTarget.removeEventListener("mouseleave", this.boundHide)
  }

  enterTouchMode() {
    if (this.touchMode) return
    this.touchMode = true
    this.detachHover()
  }

  // Au clic de souris on ne fait rien : le survol s'en occupe déjà, et un clic
  // qui referme ce que le survol vient d'ouvrir passe pour un bug.
  toggle(event) {
    if (!this.touchMode) return
    event.preventDefault()
    event.stopPropagation()
    if (this.popoverTarget.classList.contains("invisible")) this.show()
    else this.hide()
  }

  // Un toucher ailleurs referme : sans ça, la bulle reste posée sur le tableau.
  dismiss(event) {
    if (this.element.contains(event.target)) return
    this.hide()
  }

  show() {
    this.cancelHide()
    const popover = this.popoverTarget

    // On mesure avant de placer : la bulle est rendue invisible mais bien
    // disposée, sinon `getBoundingClientRect` renvoie la taille d'avant.
    popover.style.position = "fixed"
    popover.style.left = "0px"
    popover.style.right = "auto"
    popover.style.top = "0px"
    popover.style.visibility = "hidden"
    popover.classList.remove("invisible")

    const rect = this.triggerTarget.getBoundingClientRect()
    const popoverRect = popover.getBoundingClientRect()
    const margin = 8

    // Alignée à droite du déclencheur, puis ramenée dans l'écran. Sur un
    // téléphone, l'alignement à droite seul la faisait sortir par la gauche.
    const maxLeft = Math.max(margin, window.innerWidth - popoverRect.width - margin)
    const left = Math.min(Math.max(margin, rect.right - popoverRect.width), maxLeft)
    popover.style.left = `${left}px`

    const spaceBelow = window.innerHeight - rect.bottom - margin
    const top = spaceBelow >= popoverRect.height
      ? rect.bottom + 6
      : Math.max(margin, rect.top - popoverRect.height - 6)
    popover.style.top = `${top}px`

    popover.style.visibility = ""
    popover.classList.remove("opacity-0", "pointer-events-none", "scale-95")
    popover.classList.add("opacity-100", "pointer-events-auto", "scale-100")
  }

  hide() {
    this.cancelHide()
    const popover = this.popoverTarget
    popover.classList.add("invisible", "opacity-0", "pointer-events-none", "scale-95")
    popover.classList.remove("opacity-100", "pointer-events-auto", "scale-100")
  }

  cancelHide() {
    if (this.hideTimeout) {
      clearTimeout(this.hideTimeout)
      this.hideTimeout = null
    }
  }

  scheduleHide() {
    this.hideTimeout = setTimeout(() => {
      this.hide()
    }, 250)
  }
}
