import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "modalTitle", "modalItems", "modalTotal", "productList", "toast"]
  static values = {
    updateUrl: { type: String, default: "/calendrier/update_day" }
  }

  connect() {
    this.currentBakeDayId = null
    this.currentItems = []
    this.products = this.loadProducts()
  }

  loadProducts() {
    const products = {}
    document.querySelectorAll("[data-variant-id]").forEach(el => {
      products[el.dataset.variantId] = {
        id: parseInt(el.dataset.variantId),
        price: parseInt(el.dataset.price),
        name: el.querySelector(".text-sm.font-medium")?.textContent || "Produit",
        variantName: el.querySelector(".text-xs.text-gray-500")?.textContent || ""
      }
    })
    return products
  }

  // Open modal for a specific bake day
  openDayModal(event) {
    const bakeDayId = event.currentTarget.dataset.bakeDayId
    const bakeDayEl = document.querySelector(`[data-bake-day-id="${bakeDayId}"]`)

    if (bakeDayEl?.dataset.canOrder === "false") {
      this.showToast("Cette date n'est plus modifiable (cut-off passé)")
      return
    }

    this.currentBakeDayId = bakeDayId
    this.currentItems = this.loadExistingItems(bakeDayId)

    this.renderModal()
    this.showModal()
  }

  loadExistingItems(bakeDayId) {
    // Load existing items from data attributes or DOM
    const orderEl = document.querySelector(`[data-bake-day-id="${bakeDayId}"] [data-order-items]`)
    if (orderEl) {
      try {
        return JSON.parse(orderEl.dataset.orderItems)
      } catch (e) {
        return []
      }
    }
    return []
  }

  renderModal() {
    if (!this.hasModalTarget) return

    // Render product list
    if (this.hasProductListTarget) {
      this.productListTarget.innerHTML = Object.values(this.products).map(product => {
        const existingItem = this.currentItems.find(i => i.product_variant_id === product.id)
        const qty = existingItem?.qty || 0

        return `
          <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg" data-variant-id="${product.id}">
            <div>
              <p class="font-medium text-gray-900">${product.name}</p>
              <p class="text-sm text-gray-500">${product.variantName} - ${(product.price / 100).toFixed(2)} €</p>
            </div>
            <div class="flex items-center gap-2">
              <button type="button"
                      class="w-8 h-8 rounded-full bg-gray-200 hover:bg-gray-300 flex items-center justify-center"
                      data-action="click->calendar#decrementQty"
                      data-variant-id="${product.id}">
                <span class="text-lg font-bold">−</span>
              </button>
              <span class="w-8 text-center font-semibold" data-qty-display="${product.id}">${qty}</span>
              <button type="button"
                      class="w-8 h-8 rounded-full bg-green-500 hover:bg-green-600 text-white flex items-center justify-center"
                      data-action="click->calendar#incrementQty"
                      data-variant-id="${product.id}">
                <span class="text-lg font-bold">+</span>
              </button>
            </div>
          </div>
        `
      }).join("")
    }

    this.updateModalTotal()
  }

  incrementQty(event) {
    const variantId = parseInt(event.currentTarget.dataset.variantId)
    this.updateItemQty(variantId, 1)
  }

  decrementQty(event) {
    const variantId = parseInt(event.currentTarget.dataset.variantId)
    this.updateItemQty(variantId, -1)
  }

  updateItemQty(variantId, delta) {
    const existingIndex = this.currentItems.findIndex(i => i.product_variant_id === variantId)

    if (existingIndex >= 0) {
      this.currentItems[existingIndex].qty = Math.max(0, this.currentItems[existingIndex].qty + delta)
      if (this.currentItems[existingIndex].qty === 0) {
        this.currentItems.splice(existingIndex, 1)
      }
    } else if (delta > 0) {
      this.currentItems.push({ product_variant_id: variantId, qty: delta })
    }

    // Update display
    const qtyDisplay = document.querySelector(`[data-qty-display="${variantId}"]`)
    if (qtyDisplay) {
      const item = this.currentItems.find(i => i.product_variant_id === variantId)
      qtyDisplay.textContent = item?.qty || 0
    }

    this.updateModalTotal()
  }

  updateModalTotal() {
    if (!this.hasModalTotalTarget) return

    const total = this.currentItems.reduce((sum, item) => {
      const product = this.products[item.product_variant_id]
      return sum + (product?.price || 0) * item.qty
    }, 0)

    this.modalTotalTarget.textContent = `${(total / 100).toFixed(2)} €`
  }

  showModal() {
    if (this.hasModalTarget) {
      this.modalTarget.classList.remove("hidden")
      document.body.classList.add("overflow-hidden")
    }
  }

  closeModal() {
    if (this.hasModalTarget) {
      this.modalTarget.classList.add("hidden")
      document.body.classList.remove("overflow-hidden")
    }
  }

  async saveOrder() {
    try {
      const response = await fetch(this.updateUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({
          bake_day_id: this.currentBakeDayId,
          items: this.currentItems
        })
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.error || "Erreur lors de la sauvegarde")
      }

      this.closeModal()
      this.showToast("Commande enregistrée !")

      // Reload page to show updated data
      setTimeout(() => window.location.reload(), 500)
    } catch (e) {
      this.showToast(e.message, "error")
    }
  }

  async deleteOrder() {
    if (!confirm("Supprimer cette commande planifiée ?")) return

    this.currentItems = []
    await this.saveOrder()
  }

  showToast(message, type = "success") {
    // Create toast element
    const toast = document.createElement("div")
    toast.className = `fixed bottom-4 right-4 px-4 py-2 rounded-lg shadow-lg text-white z-50 ${
      type === "error" ? "bg-red-500" : "bg-green-500"
    }`
    toast.textContent = message
    document.body.appendChild(toast)

    setTimeout(() => {
      toast.remove()
    }, 3000)
  }

  // Drag and drop functionality
  dragStart(event) {
    event.dataTransfer.setData("text/plain", event.currentTarget.dataset.variantId)
    event.currentTarget.classList.add("opacity-50")
  }

  dragEnd(event) {
    event.currentTarget.classList.remove("opacity-50")
  }

  dragOver(event) {
    event.preventDefault()
    if (event.currentTarget.dataset.canOrder === "true") {
      event.currentTarget.classList.add("ring-2", "ring-green-500")
    }
  }

  dragLeave(event) {
    event.currentTarget.classList.remove("ring-2", "ring-green-500")
  }

  async drop(event) {
    event.preventDefault()
    event.currentTarget.classList.remove("ring-2", "ring-green-500")

    const bakeDayEl = event.currentTarget
    if (bakeDayEl.dataset.canOrder !== "true") {
      this.showToast("Cette date n'est plus modifiable", "error")
      return
    }

    const variantId = parseInt(event.dataTransfer.getData("text/plain"))
    const bakeDayId = bakeDayEl.dataset.bakeDayId

    // Quick add: add 1 item directly
    try {
      const response = await fetch(this.updateUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({
          bake_day_id: bakeDayId,
          items: [{ product_variant_id: variantId, qty: 1 }]
        })
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.error || "Erreur")
      }

      this.showToast("Produit ajouté !")
      setTimeout(() => window.location.reload(), 500)
    } catch (e) {
      this.showToast(e.message, "error")
    }
  }
}
