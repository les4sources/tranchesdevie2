import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="quantity-selector"
export default class extends Controller {
  static targets = ["input", "display"]
  static values = { 
    min: { type: Number, default: 1 },
    max: { type: Number, default: 99 }
  }

  connect() {
    this.updateDisplay()
  }

  increment(event) {
    event.preventDefault()
    const currentValue = parseInt(this.inputTarget.value || this.minValue, 10)
    const newValue = Math.min(currentValue + 1, this.maxValue)
    this.setValue(newValue)
  }

  decrement(event) {
    event.preventDefault()
    const currentValue = parseInt(this.inputTarget.value || this.minValue, 10)
    const newValue = Math.max(currentValue - 1, this.minValue)
    this.setValue(newValue)
  }

  setValue(value) {
    const clampedValue = Math.max(this.minValue, Math.min(value, this.maxValue))
    this.inputTarget.value = clampedValue
    this.updateDisplay()
  }

  updateDisplay() {
    if (this.hasDisplayTarget) {
      this.displayTarget.textContent = this.inputTarget.value || this.minValue
    }
  }
}

