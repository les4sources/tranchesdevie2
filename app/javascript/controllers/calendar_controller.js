import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "modalTitle", "modalItems", "modalTotal", "productList", "toast", "balanceIndicator", "saveBtn", "modalForm", "modalSuccess"]
  static values = {
    updateUrl: { type: String, default: "/calendrier/update_day" },
    walletBalance: { type: Number, default: 0 },
    committed: { type: Number, default: 0 },
    reloadUrl: { type: String, default: "/portefeuille/recharger" },
    skipWallet: { type: Boolean, default: false }
  }

  connect() {
    this.currentBakeDayId = null
    this.currentItems = []
    this.currentOrderOriginalTotal = 0
    this.products = this.loadProducts()
    this.highlightSavedCard()
  }

  loadProducts() {
    const products = {}
    document.querySelectorAll("[data-variant-id]").forEach(el => {
      products[el.dataset.variantId] = {
        id: parseInt(el.dataset.variantId),
        price: parseInt(el.dataset.price),
        productName: el.dataset.productName || el.querySelector(".text-sm.font-medium")?.textContent || "Produit",
        productCategory: el.dataset.productCategory || "",
        variantName: el.dataset.variantName || el.querySelector(".text-xs.text-gray-500")?.textContent || ""
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

    // Calculate original total of this order (to exclude from committed)
    this.currentOrderOriginalTotal = this.calculateItemsTotal(this.currentItems)

    // Update modal title with bake day date
    const bakeDate = bakeDayEl?.dataset.bakeDate
    if (bakeDate && this.hasModalTitleTarget) {
      this.modalTitleTarget.textContent = `Ma commande du ${bakeDate}`
    }

    this.renderModal()
    this.showModal()
  }

  loadExistingItems(bakeDayId) {
    const bakeDayEl = document.querySelector(`[data-bake-day-id="${bakeDayId}"]`)
    if (bakeDayEl?.dataset.orderItems) {
      try {
        return JSON.parse(bakeDayEl.dataset.orderItems)
      } catch (e) {
        return []
      }
    }
    return []
  }

  calculateItemsTotal(items) {
    return items.reduce((sum, item) => {
      const product = this.products[item.product_variant_id]
      return sum + (product?.price || 0) * item.qty
    }, 0)
  }

  get availableForCurrentOrder() {
    // Available = wallet balance - committed + this order's original total (since it will be replaced)
    return this.walletBalanceValue - this.committedValue + this.currentOrderOriginalTotal
  }

  renderModal() {
    if (!this.hasModalTarget) return

    if (this.hasProductListTarget) {
      // Group variants by category then by product name
      const byCategory = {}
      Object.values(this.products).forEach(variant => {
        const cat = variant.productCategory || "Autres"
        if (!byCategory[cat]) byCategory[cat] = {}
        if (!byCategory[cat][variant.productName]) byCategory[cat][variant.productName] = []
        byCategory[cat][variant.productName].push(variant)
      })
      // Sort variants within each product by price ascending
      Object.values(byCategory).forEach(products => {
        Object.values(products).forEach(variants => variants.sort((a, b) => a.price - b.price))
      })

      this.productListTarget.innerHTML = Object.entries(byCategory).map(([categoryName, products]) => {
        const productBlocks = Object.entries(products).map(([productName, variants]) => {
          const variantRows = variants.map(variant => {
            const existingItem = this.currentItems.find(i => i.product_variant_id === variant.id)
            const qty = existingItem?.qty || 0

            return `
              <div class="flex items-center justify-between py-2 pl-3" data-variant-id="${variant.id}">
                <div>
                  <p class="text-sm text-gray-600">${variant.variantName} — ${(variant.price / 100).toFixed(2)} €</p>
                </div>
                <div class="flex items-center gap-2">
                  <button type="button"
                          class="w-8 h-8 rounded-full bg-gray-200 hover:bg-gray-300 flex items-center justify-center"
                          data-action="click->calendar#decrementQty"
                          data-variant-id="${variant.id}">
                    <span class="text-lg font-bold">−</span>
                  </button>
                  <span class="w-8 text-center font-semibold" data-qty-display="${variant.id}">${qty}</span>
                  <button type="button"
                          class="w-8 h-8 rounded-full bg-green-500 hover:bg-green-600 text-white flex items-center justify-center"
                          data-action="click->calendar#incrementQty"
                          data-variant-id="${variant.id}">
                    <span class="text-lg font-bold">+</span>
                  </button>
                </div>
              </div>
            `
          }).join("")

          return `
            <div class="bg-gray-50 rounded-lg p-3">
              <p class="font-medium text-gray-900 mb-1">${productName}</p>
              <div class="space-y-1">${variantRows}</div>
            </div>
          `
        }).join("")

        return `
          <div class="space-y-2">
            <p class="text-xs font-semibold uppercase tracking-wide text-gray-500">${categoryName}</p>
            ${productBlocks}
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
    const total = this.calculateItemsTotal(this.currentItems)
    const available = this.availableForCurrentOrder
    const remaining = available - total

    if (this.hasModalTotalTarget) {
      this.modalTotalTarget.textContent = `${(total / 100).toFixed(2)} €`
    }

    if (!this.skipWalletValue) {
      // Update balance indicator
      if (this.hasBalanceIndicatorTarget) {
        if (total === 0) {
          this.balanceIndicatorTarget.innerHTML = `
            <p class="text-gray-500">Solde disponible : ${(available / 100).toFixed(2)} €</p>
          `
        } else if (remaining >= 0) {
          this.balanceIndicatorTarget.innerHTML = `
            <p class="text-green-600">Solde restant après cette commande : ${(remaining / 100).toFixed(2)} €</p>
          `
        } else {
          this.balanceIndicatorTarget.innerHTML = `
            <p class="text-red-600 font-medium">Solde insuffisant — il manque ${(Math.abs(remaining) / 100).toFixed(2)} €</p>
            <a href="${this.reloadUrlValue}" class="text-red-600 underline text-xs">Recharger mon portefeuille</a>
          `
        }
      }

      // Enable/disable save button
      if (this.hasSaveBtnTarget) {
        const canSave = total === 0 || remaining >= 0
        this.saveBtnTarget.disabled = !canSave
      }
    }
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
    // Reset modal panels for next opening
    if (this.hasModalFormTarget) {
      this.modalFormTarget.classList.remove("hidden")
    }
    if (this.hasModalSuccessTarget) {
      this.modalSuccessTarget.classList.add("hidden")
    }
  }

  async saveOrder() {
    if (this.hasSaveBtnTarget) {
      this.saveBtnTarget.disabled = true
      this.saveBtnTarget.textContent = "Enregistrement..."
    }

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

      const bakeDayEl = document.querySelector(`[data-bake-day-id="${this.currentBakeDayId}"]`)
      const bakeDate = bakeDayEl?.dataset.bakeDate || ""
      const totalEuros = (this.calculateItemsTotal(this.currentItems) / 100).toFixed(2)
      const summary = this.buildOrderSummary()
      const isEmpty = this.currentItems.length === 0

      this.showModalSuccess(bakeDate, totalEuros, summary, isEmpty)
    } catch (e) {
      this.showToast(e.message, "error")
      if (this.hasSaveBtnTarget) {
        this.saveBtnTarget.disabled = false
        this.saveBtnTarget.textContent = "Enregistrer"
      }
    }
  }

  async deleteOrder() {
    if (!confirm("Vider cette commande planifiée ?")) return

    this.currentItems = []
    await this.saveOrder()
  }

  buildOrderSummary() {
    return this.currentItems.map(item => {
      const product = this.products[item.product_variant_id]
      return `${product?.productName || "Produit"} x${item.qty}`
    }).join(", ")
  }

  showModalSuccess(bakeDate, totalEuros, summary, isEmpty) {
    if (this.hasModalFormTarget) {
      this.modalFormTarget.classList.add("hidden")
    }

    if (this.hasModalSuccessTarget) {
      const message = isEmpty
        ? `Votre commande pour le ${bakeDate} a bien été annulée.`
        : `C'est noté !\nVotre commande pour le ${bakeDate} est bien enregistrée.`

      this.modalSuccessTarget.innerHTML = `
        <div class="text-center py-6">
          <div class="w-16 h-16 ${isEmpty ? "bg-gray-100" : "bg-green-100"} rounded-full flex items-center justify-center mx-auto mb-4">
            <svg class="w-8 h-8 ${isEmpty ? "text-gray-500" : "text-green-600"}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
            </svg>
          </div>
          <p class="text-lg font-semibold text-gray-900 mb-3 whitespace-pre-line">${message}</p>
          ${!isEmpty ? `
            <p class="text-sm text-gray-600 mb-1">${summary}</p>
            <p class="text-xl font-bold text-green-600 mb-2">${totalEuros} €</p>
          ` : ""}
          <button type="button"
                  class="mt-4 px-6 py-3 bg-green-600 text-white rounded-lg hover:bg-green-700 text-base font-medium"
                  data-action="click->calendar#closeModalAndReload">
            Parfait, merci !
          </button>
        </div>
      `
      this.modalSuccessTarget.classList.remove("hidden")
    }
  }

  closeModalAndReload() {
    this.closeModal()
    window.location.hash = `highlight-${this.currentBakeDayId}`
    window.location.reload()
  }

  highlightSavedCard() {
    const hash = window.location.hash
    if (!hash.startsWith("#highlight-")) return

    const bakeDayId = hash.replace("#highlight-", "")
    const card = document.querySelector(`[data-bake-day-id="${bakeDayId}"]`)
    if (!card) return

    card.scrollIntoView({ behavior: "smooth", block: "center" })
    card.classList.add("ring-2", "ring-green-500", "bg-green-50")

    setTimeout(() => {
      card.classList.add("transition-all", "duration-1000")
      card.classList.remove("ring-2", "ring-green-500", "bg-green-50")
    }, 2000)

    history.replaceState(null, "", window.location.pathname)
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

  celebrateDrop(card, productName) {
    // 1. Flash the card green with a scale pulse
    card.style.transition = "transform 0.3s cubic-bezier(0.34, 1.56, 0.64, 1), box-shadow 0.3s ease"
    card.classList.add("ring-2", "ring-green-500", "bg-green-50")
    card.style.transform = "scale(1.03)"
    card.style.boxShadow = "0 0 20px rgba(34, 197, 94, 0.4)"

    // 2. Burst tiny particles from the card center
    const rect = card.getBoundingClientRect()
    const cx = rect.left + rect.width / 2
    const cy = rect.top + rect.height / 2
    for (let i = 0; i < 12; i++) {
      const dot = document.createElement("div")
      dot.style.cssText = `
        position:fixed; z-index:9999; pointer-events:none;
        width:8px; height:8px; border-radius:50%;
        left:${cx}px; top:${cy}px;
        background:${["#22c55e", "#86efac", "#fbbf24", "#f9a8d4"][i % 4]};
        transition: all 0.7s cubic-bezier(0.25, 0.46, 0.45, 0.94);
        opacity:1;
      `
      document.body.appendChild(dot)
      const angle = (i / 12) * Math.PI * 2
      const dist = 40 + Math.random() * 50
      requestAnimationFrame(() => {
        dot.style.transform = `translate(${Math.cos(angle) * dist}px, ${Math.sin(angle) * dist}px) scale(0)`
        dot.style.opacity = "0"
      })
      setTimeout(() => dot.remove(), 800)
    }

    // 3. Show inline label on the card
    const badge = document.createElement("span")
    badge.textContent = `+ ${productName}`
    badge.style.cssText = `
      position:absolute; right:12px; top:50%; transform:translateY(-50%) scale(0.8);
      background:#22c55e; color:white; font-size:13px; font-weight:600;
      padding:3px 10px; border-radius:9999px; white-space:nowrap;
      transition: all 0.35s cubic-bezier(0.34, 1.56, 0.64, 1); opacity:0;
    `
    card.style.position = "relative"
    card.appendChild(badge)
    requestAnimationFrame(() => {
      badge.style.opacity = "1"
      badge.style.transform = "translateY(-50%) scale(1)"
    })

    // 4. Settle back down
    setTimeout(() => {
      card.style.transform = "scale(1)"
      card.style.boxShadow = ""
      badge.style.opacity = "0"
      badge.style.transform = "translateY(-50%) scale(0.8)"
    }, 1200)

    setTimeout(() => {
      card.classList.remove("ring-2", "ring-green-500", "bg-green-50")
      badge.remove()
    }, 1600)
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

    // Merge with existing items
    const existingItems = this.loadExistingItems(bakeDayId)
    const existingIndex = existingItems.findIndex(i => i.product_variant_id === variantId)
    if (existingIndex >= 0) {
      existingItems[existingIndex].qty += 1
    } else {
      existingItems.push({ product_variant_id: variantId, qty: 1 })
    }

    // Check balance before sending (skip for internal customers)
    if (!this.skipWalletValue) {
      const existingTotal = this.calculateItemsTotal(this.loadExistingItems(bakeDayId))
      const newTotal = this.calculateItemsTotal(existingItems)
      const available = this.walletBalanceValue - this.committedValue + existingTotal
      if (newTotal > available) {
        this.showToast("Solde insuffisant — rechargez votre portefeuille", "error")
        return
      }
    }

    try {
      const response = await fetch(this.updateUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({
          bake_day_id: bakeDayId,
          items: existingItems
        })
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.error || "Erreur")
      }

      const product = this.products[variantId]
      this.celebrateDrop(bakeDayEl, product?.productName || "Produit")
      setTimeout(() => {
        window.location.hash = `highlight-${bakeDayId}`
        window.location.reload()
      }, 1800)
    } catch (e) {
      this.showToast(e.message, "error")
    }
  }
}
