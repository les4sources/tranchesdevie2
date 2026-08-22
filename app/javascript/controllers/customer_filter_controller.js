import { Controller } from "@hotwired/stimulus"

// Filtre client de la page Commandes.
//
// Recherche vivante : on tape un nom, un e-mail ou un numéro de téléphone, le
// contrôleur interroge /admin/customers/search et propose les clients qui
// collent. Choisir une proposition verrouille le filtre sur ce client précis
// (customer_id) et soumet le formulaire ; taper puis valider sans rien choisir
// laisse la recherche libre côté serveur (q). Sans JS, le champ reste un simple
// champ texte qui fonctionne à la soumission — la page ne dépend pas d'ici.
export default class extends Controller {
  static targets = ["input", "results", "customerId", "clear", "status"]
  static values = { url: String }

  connect() {
    this.results = []
    this.highlighted = -1
    this.pending = null
    this.lastQuery = null
    this.onDocumentClick = this.onDocumentClick.bind(this)
    this.onDocumentKeydown = this.onDocumentKeydown.bind(this)
    document.addEventListener("click", this.onDocumentClick)
    document.addEventListener("keydown", this.onDocumentKeydown)
    this.toggleClear()
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
    document.removeEventListener("keydown", this.onDocumentKeydown)
    if (this.debounce) clearTimeout(this.debounce)
    if (this.pending) this.pending.abort()
  }

  // La saisie invalide toute sélection précédente : on repart d'une recherche
  // libre tant que l'utilisatrice n'a pas cliqué une proposition.
  search() {
    this.customerIdTarget.value = ""
    this.toggleClear()

    const query = this.inputTarget.value.trim()
    if (this.debounce) clearTimeout(this.debounce)

    if (query.length < 2) {
      this.close()
      return
    }

    this.debounce = setTimeout(() => this.fetchResults(query), 180)
  }

  async fetchResults(query) {
    if (this.pending) this.pending.abort()
    const controller = new AbortController()
    this.pending = controller

    try {
      const response = await fetch(`${this.urlValue}?q=${encodeURIComponent(query)}`, {
        headers: { Accept: "application/json" },
        signal: controller.signal
      })
      if (!response.ok) throw new Error(response.statusText)

      const payload = await response.json()
      // Une réponse en retard ne doit pas écraser une saisie plus récente.
      if (payload.query !== this.inputTarget.value.trim()) return

      this.results = payload.results || []
      this.lastQuery = payload.query
      this.render()
    } catch (error) {
      if (error.name !== "AbortError") this.close()
    } finally {
      if (this.pending === controller) this.pending = null
    }
  }

  render() {
    this.highlighted = -1
    this.resultsTarget.innerHTML = ""

    if (this.results.length === 0) {
      this.resultsTarget.appendChild(this.emptyState())
    } else {
      this.results.forEach((customer, index) => {
        this.resultsTarget.appendChild(this.row(customer, index))
      })
      this.resultsTarget.appendChild(this.hint())
    }

    this.open()
  }

  emptyState() {
    const el = document.createElement("div")
    el.className = "px-4 py-6 text-center"
    el.innerHTML = `
      <p class="text-sm font-semibold" style="color: var(--text-strong);">Aucun mangeur trouvé</p>
      <p class="mt-1 text-xs" style="color: var(--text-muted);">Essayez un prénom, un début d'e-mail ou les derniers chiffres du GSM.</p>
    `
    return el
  }

  hint() {
    const el = document.createElement("div")
    el.className = "flex items-center justify-between border-t px-4 py-2 text-[11px]"
    el.style.borderColor = "var(--border-subtle)"
    el.style.background = "var(--surface-inset)"
    el.style.color = "var(--text-muted)"
    el.innerHTML = `
      <span>↑ ↓ pour naviguer · ⏎ pour choisir</span>
      <span>Échap pour fermer</span>
    `
    return el
  }

  row(customer, index) {
    const row = document.createElement("button")
    row.type = "button"
    row.role = "option"
    row.id = `customer-filter-option-${index}`
    row.setAttribute("aria-selected", "false")
    row.dataset.index = index
    row.className =
      "adm-option group flex w-full items-center gap-3 border-l-2 border-transparent px-4 py-2 text-left"

    const orders =
      customer.orders_count === 1 ? "1 commande" : `${customer.orders_count} commandes`
    const contact = [customer.email, this.formatPhone(customer.phone)].filter(Boolean).join(" · ")

    row.innerHTML = `
      <span class="flex h-8 w-8 flex-none items-center justify-center rounded-full text-[11px] font-semibold uppercase"
            style="background: var(--sage-200); color: var(--sage-700);">
        ${this.escape(this.initials(customer.name))}
      </span>
      <span class="min-w-0 flex-1">
        <span class="block truncate text-sm font-semibold" style="color: var(--text-strong);">${this.highlight(customer.name)}</span>
        <span class="block truncate text-xs" style="color: var(--text-muted);">${contact ? this.highlight(contact) : "—"}</span>
      </span>
      <span class="adm-chip adm-chip-neutral flex-none">${orders}</span>
    `

    row.addEventListener("click", () => this.select(index))
    row.addEventListener("mouseenter", () => {
      this.highlighted = index
      this.paintHighlight()
    })
    return row
  }

  select(index) {
    const customer = this.results[index]
    if (!customer) return

    this.customerIdTarget.value = customer.id
    this.inputTarget.value = customer.name
    this.close()
    this.element.closest("form").requestSubmit()
  }

  clear() {
    this.inputTarget.value = ""
    this.customerIdTarget.value = ""
    this.close()
    this.toggleClear()
    this.inputTarget.focus()
  }

  keydown(event) {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      if (!this.isOpen) return
      event.preventDefault()
      const delta = event.key === "ArrowDown" ? 1 : -1
      const count = this.results.length
      if (count === 0) return
      this.highlighted = (this.highlighted + delta + count) % count
      this.paintHighlight()
    } else if (event.key === "Enter") {
      // Entrée sur une proposition surlignée = sélection ; sinon on laisse le
      // formulaire partir en recherche libre.
      if (this.isOpen && this.highlighted >= 0) {
        event.preventDefault()
        this.select(this.highlighted)
      }
    } else if (event.key === "Escape") {
      this.close()
    }
  }

  paintHighlight() {
    Array.from(this.resultsTarget.querySelectorAll("button[data-index]")).forEach((row, index) => {
      const active = index === this.highlighted
      row.classList.toggle("adm-option-active", active)
      row.setAttribute("aria-selected", active ? "true" : "false")
      if (active) {
        this.inputTarget.setAttribute("aria-activedescendant", row.id)
        row.scrollIntoView({ block: "nearest" })
      }
    })
  }

  open() {
    this.isOpen = true
    this.resultsTarget.classList.remove("hidden")
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.isOpen = false
    this.highlighted = -1
    this.resultsTarget.classList.add("hidden")
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
  }

  focus() {
    if (this.results.length > 0 && this.inputTarget.value.trim().length >= 2) this.open()
  }

  toggleClear() {
    if (!this.hasClearTarget) return
    this.clearTarget.classList.toggle("hidden", this.inputTarget.value.trim() === "")
  }

  onDocumentClick(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  // « / » met le curseur dans la recherche depuis n'importe où sur la page.
  onDocumentKeydown(event) {
    if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) return
    const tag = document.activeElement?.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return
    event.preventDefault()
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  initials(name) {
    return (name || "?")
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0])
      .join("")
  }

  formatPhone(phone) {
    if (!phone) return ""
    const belgian = phone.match(/^\+32(\d{3})(\d{2})(\d{2})(\d{2})$/)
    if (belgian) return `0${belgian[1]} ${belgian[2]} ${belgian[3]} ${belgian[4]}`
    return phone
  }

  // Souligne la portion saisie dans le résultat, pour qu'on voie *pourquoi*
  // une ligne remonte (le e-mail, le GSM, le nom…).
  highlight(text) {
    const escaped = this.escape(text)
    const query = (this.lastQuery || "").trim()
    if (query.length < 2) return escaped

    const needle = this.escape(query).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    return escaped.replace(
      new RegExp(needle, "ig"),
      (match) => `<mark class="adm-mark">${match}</mark>`
    )
  }

  escape(text) {
    const div = document.createElement("div")
    div.textContent = text == null ? "" : String(text)
    return div.innerHTML
  }
}
