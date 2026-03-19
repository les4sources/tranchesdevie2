import { Controller } from "@hotwired/stimulus"

// Fixed-position tooltip that avoids overflow clipping from parent containers.
// Repositions on show to stay within viewport bounds.
export default class extends Controller {
  static targets = ["trigger", "popover"]

  connect() {
    this.hideTimeout = null
    this.boundShow = this.show.bind(this)
    this.boundHide = this.scheduleHide.bind(this)
    this.boundCancelHide = this.cancelHide.bind(this)

    this.triggerTarget.addEventListener("mouseenter", this.boundShow)
    this.triggerTarget.addEventListener("mouseleave", this.boundHide)
    this.popoverTarget.addEventListener("mouseenter", this.boundCancelHide)
    this.popoverTarget.addEventListener("mouseleave", this.boundHide)
  }

  disconnect() {
    this.triggerTarget.removeEventListener("mouseenter", this.boundShow)
    this.triggerTarget.removeEventListener("mouseleave", this.boundHide)
    this.popoverTarget.removeEventListener("mouseenter", this.boundCancelHide)
    this.popoverTarget.removeEventListener("mouseleave", this.boundHide)
    if (this.hideTimeout) clearTimeout(this.hideTimeout)
  }

  show() {
    this.cancelHide()
    const rect = this.triggerTarget.getBoundingClientRect()
    const popover = this.popoverTarget

    popover.style.position = "fixed"
    popover.style.left = "auto"

    const rightOffset = window.innerWidth - rect.right
    popover.style.right = `${rightOffset}px`

    popover.style.visibility = "hidden"
    popover.style.display = "block"
    popover.classList.remove("invisible")

    const popoverRect = popover.getBoundingClientRect()
    const spaceBelow = window.innerHeight - rect.bottom - 8
    if (spaceBelow >= popoverRect.height) {
      popover.style.top = `${rect.bottom + 6}px`
    } else {
      popover.style.top = `${rect.top - popoverRect.height - 6}px`
    }

    popover.style.visibility = ""
    popover.style.display = ""
    popover.classList.remove("opacity-0", "pointer-events-none", "scale-95")
    popover.classList.add("opacity-100", "pointer-events-auto", "scale-100")
  }

  cancelHide() {
    if (this.hideTimeout) {
      clearTimeout(this.hideTimeout)
      this.hideTimeout = null
    }
  }

  scheduleHide() {
    this.hideTimeout = setTimeout(() => {
      const popover = this.popoverTarget
      popover.classList.add("invisible", "opacity-0", "pointer-events-none", "scale-95")
      popover.classList.remove("opacity-100", "pointer-events-auto", "scale-100")
      this.hideTimeout = null
    }, 250)
  }
}
