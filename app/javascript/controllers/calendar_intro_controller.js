import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "slide", "progressDot", "prevBtn", "nextBtn", "navBar"]
  static values = {
    autoOpen: Boolean,
    markSeenUrl: String,
    currentSlide: { type: Number, default: 0 }
  }

  connect() {
    this.seenSent = false
    this.boundEscape = this.handleEscape.bind(this)
    if (this.autoOpenValue) {
      this.open()
    }
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundEscape)
  }

  open() {
    this.currentSlideValue = 0
    this.updateSlideDisplay()
    this.modalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    document.addEventListener("keydown", this.boundEscape)
  }

  close() {
    this.modalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
    document.removeEventListener("keydown", this.boundEscape)
    this.markSeen()
  }

  skip() {
    this.close()
  }

  next() {
    if (this.currentSlideValue < this.slideTargets.length - 1) {
      this.currentSlideValue += 1
      this.updateSlideDisplay()
    }
  }

  prev() {
    if (this.currentSlideValue > 0) {
      this.currentSlideValue -= 1
      this.updateSlideDisplay()
    }
  }

  goToCta() {
    this.markSeen()
    window.location.href = this.modalTarget.dataset.calendarIntroCtaUrl || "/portefeuille/recharger"
  }

  overlayClick(event) {
    if (event.target === event.currentTarget) {
      this.close()
    }
  }

  handleEscape(event) {
    if (event.key === "Escape") this.close()
  }

  updateSlideDisplay() {
    this.slideTargets.forEach((slide, index) => {
      slide.classList.toggle("hidden", index !== this.currentSlideValue)
    })
    if (this.hasProgressDotTarget) {
      this.progressDotTargets.forEach((dot, index) => {
        dot.classList.toggle("bg-green-600", index === this.currentSlideValue)
        dot.classList.toggle("bg-gray-300", index !== this.currentSlideValue)
      })
    }
    if (this.hasPrevBtnTarget) {
      this.prevBtnTarget.disabled = this.currentSlideValue === 0
    }
    if (this.hasNavBarTarget) {
      const isLastSlide = this.currentSlideValue === this.slideTargets.length - 1
      this.navBarTarget.classList.toggle("hidden", isLastSlide)
    }
  }

  markSeen() {
    if (this.seenSent || !this.markSeenUrlValue) return
    this.seenSent = true
    fetch(this.markSeenUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
        "Accept": "application/json"
      }
    }).catch(() => {
      // If it fails, the modal will simply reappear next visit — acceptable.
      this.seenSent = false
    })
  }
}
