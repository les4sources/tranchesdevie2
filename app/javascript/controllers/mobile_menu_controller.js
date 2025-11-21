import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "button"]

  connect() {
    this.handleClickOutside = this.handleClickOutside.bind(this)
    this.handleEscape = this.handleEscape.bind(this)
  }

  toggle() {
    if (this.isOpen()) {
      this.close()
    } else {
      this.open()
    }
  }

  open() {
    this.menuTarget.classList.remove("hidden")
    document.body.style.overflow = "hidden"
    document.addEventListener("click", this.handleClickOutside)
    document.addEventListener("keydown", this.handleEscape)
  }

  close() {
    this.menuTarget.classList.add("hidden")
    document.body.style.overflow = ""
    document.removeEventListener("click", this.handleClickOutside)
    document.removeEventListener("keydown", this.handleEscape)
  }

  isOpen() {
    return !this.menuTarget.classList.contains("hidden")
  }

  handleClickOutside(event) {
    if (!this.menuTarget.contains(event.target) && !this.buttonTarget.contains(event.target)) {
      this.close()
    }
  }

  handleEscape(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }
}

