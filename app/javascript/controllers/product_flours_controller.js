import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "item", "empty", "floursData"]

  connect() {
    this.flourIndex = Date.now()
    this.loadFlours()
    this.updateEmptyState()
  }

  loadFlours() {
    try {
      const dataElement = this.floursDataTarget
      this.flours = JSON.parse(dataElement.textContent)
    } catch (e) {
      this.flours = []
    }
  }

  add(event) {
    event.preventDefault()
    this.hideEmptyState()

    const index = this.flourIndex++
    const template = this.createFlourTemplate(index)
    this.containerTarget.insertAdjacentHTML("beforeend", template)
  }

  remove(event) {
    event.preventDefault()
    const item = event.target.closest("[data-product-flours-target='item']")
    if (!item) return

    const destroyField = item.querySelector(".destroy-field")

    if (destroyField && item.querySelector("input[name*='[id]']")) {
      destroyField.value = "true"
      item.style.display = "none"
    } else {
      item.remove()
    }

    this.updateEmptyState()
  }

  createFlourTemplate(index) {
    const optionsHtml = this.flours
      .map(f => `<option value="${f.id}">${f.name}</option>`)
      .join("")

    const inputClass = "block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 focus:outline-none"

    return `
      <div class="product-flour-item border border-gray-200 rounded-lg p-4 bg-gray-50 flex flex-col gap-4 sm:flex-row sm:items-center sm:gap-4" data-product-flours-target="item">
        <div class="flex-1 min-w-0">
          <select name="product[product_flours_attributes][${index}][flour_id]" class="${inputClass}">
            <option value="">Sélectionner une farine</option>
            ${optionsHtml}
          </select>
        </div>
        <div class="flex items-center gap-2 sm:min-w-[8rem]">
          <input type="number" step="1" min="1" max="100" name="product[product_flours_attributes][${index}][percentage]" class="${inputClass} w-20" placeholder="%">
          <span class="text-sm text-gray-500 whitespace-nowrap">%</span>
        </div>
        <div class="flex-shrink-0">
          <input type="hidden" name="product[product_flours_attributes][${index}][_destroy]" value="false" class="destroy-field">
          <button type="button" class="px-3 py-1 text-sm bg-red-600 text-white rounded-md hover:bg-red-700 w-full sm:w-auto" data-action="product-flours#remove">Supprimer</button>
        </div>
      </div>
    `
  }

  updateEmptyState() {
    const visibleItems = this.itemTargets.filter(
      item => item.style.display !== "none"
    )
    const isEmpty = visibleItems.length === 0

    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("hidden", !isEmpty)
    }
  }

  hideEmptyState() {
    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.add("hidden")
    }
  }
}
