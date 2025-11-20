import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "tab"]
  static values = {
    active: String
  }

  connect() {
    if (!this.activeValue && this.tabTargets.length > 0) {
      this.activeValue = this.tabTargets[0].dataset.tab
    }
    this.update()
  }

  show(event) {
    this.activeValue = event.currentTarget.dataset.tab
    this.update()
  }

  update() {
    this.tabTargets.forEach((tab) => {
      const isActive = tab.dataset.tab === this.activeValue
      tab.classList.toggle("bg-white", isActive)
      tab.classList.toggle("text-gray-900", isActive)
      tab.classList.toggle("shadow", isActive)
      tab.classList.toggle("bg-gray-100", !isActive)
      tab.setAttribute("aria-selected", isActive)
    })

    this.panelTargets.forEach((panel) => {
      const isVisible = panel.dataset.panel === this.activeValue
      panel.classList.toggle("hidden", !isVisible)
    })
  }
}


