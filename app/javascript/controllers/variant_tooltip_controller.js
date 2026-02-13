import { Controller } from "@hotwired/stimulus"

// Shows a tooltip popover on hover with ingredients list and edit link.
// Uses a short delay on mouseleave so the user can move to the popover and click.
export default class extends Controller {
  static targets = ["popover"]

  connect() {
    this.hideTimeout = null
    this.boundShow = this.show.bind(this)
    this.boundScheduleHide = this.scheduleHide.bind(this)
    this.element.addEventListener("mouseenter", this.boundShow)
    this.element.addEventListener("mouseleave", this.boundScheduleHide)
    if (this.hasPopoverTarget) {
      this.popoverTarget.addEventListener("mouseenter", this.boundShow)
      this.popoverTarget.addEventListener("mouseleave", this.boundScheduleHide)
    }
  }

  disconnect() {
    this.element.removeEventListener("mouseenter", this.boundShow)
    this.element.removeEventListener("mouseleave", this.boundScheduleHide)
    if (this.hasPopoverTarget) {
      this.popoverTarget.removeEventListener("mouseenter", this.boundShow)
      this.popoverTarget.removeEventListener("mouseleave", this.boundScheduleHide)
    }
    if (this.hideTimeout) clearTimeout(this.hideTimeout)
  }

  show() {
    if (this.hideTimeout) {
      clearTimeout(this.hideTimeout)
      this.hideTimeout = null
    }
    this.popoverTarget.classList.remove("invisible", "opacity-0", "pointer-events-none")
    this.popoverTarget.classList.add("opacity-100", "pointer-events-auto")
  }

  scheduleHide() {
    this.hideTimeout = setTimeout(() => {
      this.popoverTarget.classList.add("invisible", "opacity-0", "pointer-events-none")
      this.popoverTarget.classList.remove("opacity-100", "pointer-events-auto")
      this.hideTimeout = null
    }, 200)
  }
}
