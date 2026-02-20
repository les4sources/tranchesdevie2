import { Controller } from "@hotwired/stimulus"

// Searchable select dropdown (Harvest/Chosen style)
// Usage:
//   <div data-controller="searchable-select" data-searchable-select-placeholder-value="Choisir...">
//     <select data-searchable-select-target="select" ...>
//       <option value="">Sélectionner</option>
//       <option value="1">Alpha</option>
//     </select>
//   </div>

export default class extends Controller {
  static targets = ["select"]
  static values = { placeholder: { type: String, default: "Choisir un client..." } }

  connect() {
    this.isOpen = false
    this.highlightedIndex = -1
    this.buildWidget()
    this.selectTarget.style.display = "none"
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener("click", this.handleOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this.handleOutsideClick)
  }

  buildWidget() {
    // Parse options from the original select
    this.options = Array.from(this.selectTarget.options)
      .filter(o => o.value !== "")
      .map(o => ({ value: o.value, label: o.text, selected: o.selected }))

    const selected = this.options.find(o => o.selected)

    // Container
    this.container = document.createElement("div")
    this.container.className = "relative mt-1"

    // Display button
    this.display = document.createElement("button")
    this.display.type = "button"
    this.display.className = "block w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-left shadow-sm " +
      "focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 focus:outline-none flex items-center justify-between"
    this.displayText = document.createElement("span")
    this.displayText.textContent = selected ? selected.label : this.placeholderValue
    this.displayText.className = selected ? "text-gray-900" : "text-gray-400"
    const chevron = document.createElement("span")
    chevron.innerHTML = `<svg class="h-4 w-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/></svg>`
    this.display.appendChild(this.displayText)
    this.display.appendChild(chevron)
    this.display.addEventListener("click", (e) => {
      e.preventDefault()
      this.toggle()
    })

    // Dropdown panel
    this.dropdown = document.createElement("div")
    this.dropdown.className = "absolute z-50 mt-1 w-full rounded-md border border-gray-200 bg-white shadow-lg hidden"
    this.dropdown.style.maxHeight = "300px"
    this.dropdown.style.display = "none"

    // Search input
    const searchWrap = document.createElement("div")
    searchWrap.className = "flex items-center border-b border-gray-200 px-3 py-2"
    searchWrap.innerHTML = `<svg class="h-4 w-4 text-gray-400 mr-2 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><circle cx="11" cy="11" r="8"/><path stroke-linecap="round" stroke-width="2" d="M21 21l-4.35-4.35"/></svg>`
    this.searchInput = document.createElement("input")
    this.searchInput.type = "text"
    this.searchInput.placeholder = "Search..."
    this.searchInput.className = "w-full text-sm text-gray-900 outline-none border-none focus:ring-0 p-0"
    this.searchInput.addEventListener("input", () => this.filterList())
    this.searchInput.addEventListener("keydown", (e) => this.handleKeydown(e))
    searchWrap.appendChild(this.searchInput)

    // Options list
    this.listEl = document.createElement("ul")
    this.listEl.className = "overflow-y-auto"
    this.listEl.style.maxHeight = "240px"

    this.dropdown.appendChild(searchWrap)
    this.dropdown.appendChild(this.listEl)

    this.container.appendChild(this.display)
    this.container.appendChild(this.dropdown)
    this.selectTarget.insertAdjacentElement("afterend", this.container)

    this.renderList(this.options)
  }

  renderList(items) {
    this.listEl.innerHTML = ""
    this.highlightedIndex = -1
    this.visibleItems = items

    if (items.length === 0) {
      const li = document.createElement("li")
      li.className = "px-3 py-2 text-sm text-gray-400"
      li.textContent = "Aucun résultat"
      this.listEl.appendChild(li)
      return
    }

    items.forEach((opt, i) => {
      const li = document.createElement("li")
      li.className = "px-3 py-2 text-sm text-gray-900 cursor-pointer hover:bg-indigo-600 hover:text-white"
      li.textContent = opt.label
      li.addEventListener("click", () => this.selectOption(opt))
      li.addEventListener("mouseenter", () => {
        this.highlightedIndex = i
        this.updateHighlight()
      })
      this.listEl.appendChild(li)
    })
  }

  filterList() {
    const q = this.searchInput.value.toLowerCase().trim()
    const filtered = q === ""
      ? this.options
      : this.options.filter(o => o.label.toLowerCase().includes(q))
    this.renderList(filtered)
  }

  selectOption(opt) {
    this.selectTarget.value = opt.value
    this.selectTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.displayText.textContent = opt.label
    this.displayText.className = "text-gray-900"
    this.close()
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.isOpen = true
    this.dropdown.style.display = "block"
    this.dropdown.classList.remove("hidden")
    this.searchInput.value = ""
    this.renderList(this.options)
    setTimeout(() => this.searchInput.focus(), 10)
  }

  close() {
    this.isOpen = false
    this.dropdown.style.display = "none"
  }

  handleOutsideClick(e) {
    if (this.isOpen && !this.container.contains(e.target)) {
      this.close()
    }
  }

  handleKeydown(e) {
    const items = this.visibleItems || []
    if (e.key === "ArrowDown") {
      e.preventDefault()
      this.highlightedIndex = Math.min(this.highlightedIndex + 1, items.length - 1)
      this.updateHighlight()
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this.highlightedIndex = Math.max(this.highlightedIndex - 1, 0)
      this.updateHighlight()
    } else if (e.key === "Enter") {
      e.preventDefault()
      if (this.highlightedIndex >= 0 && items[this.highlightedIndex]) {
        this.selectOption(items[this.highlightedIndex])
      }
    } else if (e.key === "Escape") {
      this.close()
    }
  }

  updateHighlight() {
    const lis = this.listEl.querySelectorAll("li")
    lis.forEach((li, i) => {
      if (i === this.highlightedIndex) {
        li.classList.add("bg-indigo-600", "text-white")
        li.scrollIntoView({ block: "nearest" })
      } else {
        li.classList.remove("bg-indigo-600", "text-white")
      }
    })
  }
}
