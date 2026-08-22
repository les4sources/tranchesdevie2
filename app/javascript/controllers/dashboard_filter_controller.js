import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row"]
  static values = {
    filter: { type: String, default: "all" }
  }

  change(event) {
    this.filterValue = event.currentTarget.dataset.filter
    this.updateButtons(event.currentTarget)
    this.applyFilter()
  }

  applyFilter() {
    this.rowTargets.forEach((row) => {
      const category = row.dataset.category
      row.classList.toggle(
        "hidden",
        this.filterValue !== "all" && this.filterValue !== category
      )
    })
  }

  updateButtons(activeButton) {
    const buttons = activeButton
      .closest("[data-filter-group]")
      ?.querySelectorAll("button")

    buttons?.forEach((button) => {
      const isActive = button === activeButton
      button.classList.toggle("bg-indigo-600", isActive)
      button.classList.toggle("text-white", isActive)
      button.classList.toggle("border-indigo-600", isActive)
      if (!isActive) {
        button.classList.remove("bg-indigo-600", "text-white", "border-indigo-600")
      }
    })
  }
}


