import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "count",
    "miniCartPanel",
    "miniCartContent",
    "miniCartWrapper",
  ]

  initialize() {
    this.buttonTimers = new WeakMap()
    this.handleDocumentClick = this.handleDocumentClick.bind(this)
    this.miniCartCloseTimeout = null
    this.miniCartAutoHideTimeout = null
  }

  connect() {
    document.addEventListener("click", this.handleDocumentClick)
  }

  disconnect() {
    document.removeEventListener("click", this.handleDocumentClick)
    this.clearMiniCartTimers()
  }

  add(event) {
    event.preventDefault()

    const form = event.target
    const submitButton = form.querySelector("[data-cart-target='button']")

    if (!submitButton) {
      form.submit()
      return
    }

    if (submitButton.dataset.cartBusy === "true") {
      return
    }

    submitButton.dataset.cartBusy = "true"
    submitButton.dataset.cartOriginalLabel ||= submitButton.innerHTML.trim()
    submitButton.disabled = true

    this.performRequest(form)
      .then((data) => {
        if (data?.cart_count !== undefined) {
          this.updateCount(data.cart_count)
        }

        if (data?.mini_cart_html) {
          this.refreshMiniCart(data.mini_cart_html)
        }

        if (data?.variant_qty !== undefined) {
          this.updateButtonQuantity(submitButton, data.variant_qty)
        } else {
          this.showTemporaryLabel(submitButton, "✔")
        }
        this.notifySuccess(data?.message)
        
        // Redirect to catalog if on product page
        const isProductPage = window.location.pathname.includes('/productions/')
        if (isProductPage) {
          setTimeout(() => {
            window.location.href = '/catalogue'
          }, 500)
        } else {
          this.openMiniCartTemporarily()
        }
      })
      .catch((error) => {
        console.error("Impossible d'ajouter le produit au panier :", error)
        this.showTemporaryLabel(submitButton, "!")
        this.notifyError(error?.message)
      })
  }

  async performRequest(form) {
    let response

    try {
      response = await fetch(form.action, {
        method: form.method || "POST",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken(),
        },
        body: new FormData(form),
      })
    } catch (error) {
      throw new Error(this.defaultErrorMessage())
    }

    const data = await response.json().catch(() => ({}))

    if (!response.ok) {
      const message = data?.error || this.defaultErrorMessage()
      throw new Error(message)
    }

    return data
  }

  updateCount(count) {
    if (!this.hasCountTarget) return

    this.countTargets.forEach((element) => {
      element.textContent = count
      element.classList.toggle("hidden", count === 0)
      this.animateBadge(element)
    })
  }

  animateBadge(element) {
    if (!element) return

    element.classList.remove("cart-bounce")
    // Force reflow to restart animation
    void element.offsetWidth
    element.classList.add("cart-bounce")

    element.addEventListener(
      "animationend",
      () => {
        element.classList.remove("cart-bounce")
      },
      { once: true },
    )
  }

  refreshMiniCart(html) {
    if (!this.hasMiniCartContentTarget) return
    this.miniCartContentTarget.innerHTML = html
  }

  openMiniCart() {
    if (!this.hasMiniCartPanelTarget) return
    this.cancelMiniCartClose()
    this.miniCartPanelTarget.classList.remove("hidden")
  }

  openMiniCartTemporarily() {
    if (!this.hasMiniCartPanelTarget) return
    this.openMiniCart()
    if (this.miniCartAutoHideTimeout) {
      clearTimeout(this.miniCartAutoHideTimeout)
    }
    this.miniCartAutoHideTimeout = setTimeout(() => {
      this.closeMiniCart()
    }, 4000)
  }

  closeMiniCart() {
    if (!this.hasMiniCartPanelTarget) return
    this.miniCartPanelTarget.classList.add("hidden")
  }

  scheduleMiniCartClose() {
    this.cancelMiniCartClose()
    this.miniCartCloseTimeout = setTimeout(() => this.closeMiniCart(), 200)
  }

  cancelMiniCartClose() {
    if (this.miniCartCloseTimeout) {
      clearTimeout(this.miniCartCloseTimeout)
      this.miniCartCloseTimeout = null
    }
  }

  toggleMiniCart(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }

    if (this.isMiniCartOpen()) {
      this.closeMiniCart()
    } else {
      this.openMiniCart()
    }
  }

  isMiniCartOpen() {
    return (
      this.hasMiniCartPanelTarget &&
      !this.miniCartPanelTarget.classList.contains("hidden")
    )
  }

  handleDocumentClick(event) {
    if (!this.hasMiniCartWrapperTarget) return
    if (!this.isMiniCartOpen()) return

    if (this.miniCartWrapperTarget.contains(event.target)) {
      return
    }

    this.closeMiniCart()
  }

  updateButtonQuantity(button, qty) {
    button.innerHTML = qty > 0 ? qty : "+"
    button.dataset.cartCurrentQty = qty
    button.disabled = false
    button.dataset.cartBusy = "false"
    
    // Clear any pending timer
    if (this.buttonTimers.has(button)) {
      clearTimeout(this.buttonTimers.get(button))
      this.buttonTimers.delete(button)
    }
  }

  showTemporaryLabel(button, label) {
    const currentQty = parseInt(button.dataset.cartCurrentQty || "0", 10)
    const originalLabel = currentQty > 0 ? currentQty : "+"

    button.innerHTML = label

    if (this.buttonTimers.has(button)) {
      clearTimeout(this.buttonTimers.get(button))
    }

    const timeoutId = setTimeout(() => {
      button.innerHTML = originalLabel
      button.disabled = false
      button.dataset.cartBusy = "false"
      this.buttonTimers.delete(button)
    }, 2000)

    this.buttonTimers.set(button, timeoutId)
  }

  notifySuccess(message) {
    const finalMessage = message || "Produit ajouté au panier."
    window.dispatchEvent(
      new CustomEvent("cart:add:success", {
        detail: { message: finalMessage, type: "success" },
      }),
    )
  }

  notifyError(message) {
    const finalMessage = message || this.defaultErrorMessage()
    window.dispatchEvent(
      new CustomEvent("cart:add:error", {
        detail: { message: finalMessage, type: "error" },
      }),
    )
  }

  defaultErrorMessage() {
    return "Un problème est survenu lors de l'ajout au panier."
  }

  clearMiniCartTimers() {
    this.cancelMiniCartClose()
    if (this.miniCartAutoHideTimeout) {
      clearTimeout(this.miniCartAutoHideTimeout)
      this.miniCartAutoHideTimeout = null
    }
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}

