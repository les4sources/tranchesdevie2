import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "item", "empty", "ingredientsData"]

  connect() {
    this.ingredientIndex = Date.now()
    this.loadIngredients()
    this.updateEmptyState()
  }

  loadIngredients() {
    try {
      const dataElement = this.ingredientsDataTarget
      this.ingredients = JSON.parse(dataElement.textContent)
    } catch (e) {
      this.ingredients = []
    }
  }

  add(event) {
    event.preventDefault()
    this.hideEmptyState()

    const index = this.ingredientIndex++
    const template = this.createIngredientTemplate(index)
    this.containerTarget.insertAdjacentHTML("beforeend", template)
  }

  remove(event) {
    event.preventDefault()
    const item = event.target.closest("[data-variant-ingredients-target='item']")
    if (!item) return

    const destroyField = item.querySelector(".destroy-field")

    if (destroyField && item.querySelector("input[name*='[id]']")) {
      // Existing record: mark for destruction and hide
      destroyField.value = "true"
      item.style.display = "none"
    } else {
      // New record: just remove from DOM
      item.remove()
    }

    this.updateEmptyState()
  }

  updateUnit(event) {
    const select = event.target
    const item = select.closest("[data-variant-ingredients-target='item']")
    const unitLabel = item.querySelector(".unit-label")

    if (!unitLabel) return

    const selectedId = parseInt(select.value)
    const ingredient = this.ingredients.find(i => i.id === selectedId)
    unitLabel.textContent = ingredient ? ingredient.unit_label : "g"
  }

  createIngredientTemplate(index) {
    const optionsHtml = this.ingredients
      .map(i => `<option value="${i.id}">${i.name}</option>`)
      .join("")

    return `
      <div class="variant-ingredient-item border border-gray-200 rounded-lg p-4 bg-gray-50 flex items-center gap-4" data-variant-ingredients-target="item">
        <div class="flex-1">
          <select name="product_variant[variant_ingredients_attributes][${index}][ingredient_id]" class="ingredient-select block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500" data-action="change->variant-ingredients#updateUnit">
            <option value="">Sélectionner un ingrédient</option>
            ${optionsHtml}
          </select>
        </div>
        <div class="w-40">
          <div class="flex items-center gap-2">
            <input type="number" step="0.01" min="0" name="product_variant[variant_ingredients_attributes][${index}][quantity]" class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500" placeholder="Quantité">
            <span class="text-sm text-gray-500 unit-label w-16">g</span>
          </div>
        </div>
        <div class="flex-shrink-0">
          <input type="hidden" name="product_variant[variant_ingredients_attributes][${index}][_destroy]" value="false" class="destroy-field">
          <button type="button" class="px-3 py-1 text-sm bg-red-600 text-white rounded-md hover:bg-red-700" data-action="variant-ingredients#remove">Supprimer</button>
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
