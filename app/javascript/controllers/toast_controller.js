import { Controller } from "@hotwired/stimulus"

const DEFAULT_DURATION = 4000

export default class extends Controller {
  static targets = ["container"]

  connect() {
    this.handleSuccess = this.handleSuccess.bind(this)
    this.handleError = this.handleError.bind(this)

    window.addEventListener("cart:add:success", this.handleSuccess)
    window.addEventListener("cart:add:error", this.handleError)
    window.addEventListener("dashboard:toast", this.handleCustomToast)
  }

  disconnect() {
    window.removeEventListener("cart:add:success", this.handleSuccess)
    window.removeEventListener("cart:add:error", this.handleError)
    window.removeEventListener("dashboard:toast", this.handleCustomToast)
  }

  handleSuccess(event) {
    const message =
      event?.detail?.message || "Produit ajouté au panier avec succès."
    this.show(message, "success")
  }

  handleError(event) {
    const message =
      event?.detail?.message || "Une erreur est survenue. Veuillez réessayer."
    this.show(message, "error")
  }

  handleCustomToast = (event) => {
    const { message, kind } = event.detail || {}
    if (!message) return
    this.show(message, kind || "info")
  }

  show(message, type = "info", duration = DEFAULT_DURATION) {
    if (!this.hasContainerTarget) return

    const toast = document.createElement("div")
    toast.setAttribute("role", "status")
    toast.className =
      "pointer-events-auto flex w-full items-center gap-3 rounded-xl px-4 py-3 text-sm shadow-lg ring-1 ring-black/5 backdrop-blur opacity-0 translate-y-2 transition duration-200 ease-out"

    const icon = document.createElement("span")
    icon.className = "material-symbols-outlined text-lg"

    if (type === "success") {
      toast.classList.add("bg-emerald-500/95", "text-white")
      icon.textContent = "check_circle"
    } else if (type === "error") {
      toast.classList.add("bg-red-500/95", "text-white")
      icon.textContent = "error"
    } else {
      toast.classList.add("bg-gray-900/90", "text-white")
      icon.textContent = "info"
    }

    const text = document.createElement("p")
    text.className = "flex-1 text-sm font-medium leading-snug"
    text.textContent = message

    const closeButton = document.createElement("button")
    closeButton.type = "button"
    closeButton.className =
      "text-white/90 transition hover:text-white focus:outline-none"
    closeButton.innerHTML = '<span class="material-symbols-outlined">close</span>'

    const remove = () => {
      toast.classList.add("opacity-0", "translate-y-1")
      setTimeout(() => {
        toast.remove()
      }, 150)
    }

    closeButton.addEventListener("click", remove)

    toast.append(icon, text, closeButton)
    this.containerTarget.appendChild(toast)

    requestAnimationFrame(() => {
      toast.classList.add("opacity-100", "translate-y-0")
    })

    setTimeout(remove, duration)
  }
}


