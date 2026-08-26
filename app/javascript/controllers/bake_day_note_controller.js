import { Controller } from "@hotwired/stimulus"

const SAVE_DELAY = 800

// Consignes du jour (#195). L'éditeur vit dans une modale, mais l'état de la
// consigne — vide ou remplie, et son contenu — reste lisible sur la page :
// c'est tout l'enjeu, une consigne opérationnelle invisible ne sert à rien.
export default class extends Controller {
  static targets = ["form", "status", "modal", "overlay", "chip", "preview", "placeholder"]
  static values = {
    url: String
  }

  connect() {
    this.timeout = null
    this.isSaving = false
    this.pending = false
  }

  disconnect() {
    clearTimeout(this.timeout)
    document.body.style.overflow = ""
  }

  open(event) {
    if (event) event.preventDefault()
    if (!this.hasModalTarget) return

    this.modalTarget.classList.remove("hidden")
    document.body.style.overflow = "hidden"
    this.editor?.focus()
  }

  // Fermer ne doit jamais perdre une saisie : la modale est simplement masquée
  // (le contenu reste dans le DOM), et un enregistrement encore en attente est
  // déclenché tout de suite plutôt qu'abandonné avec le timer.
  close(event) {
    if (event) event.preventDefault()
    if (!this.hasModalTarget) return

    this.modalTarget.classList.add("hidden")
    document.body.style.overflow = ""

    if (this.pending) {
      clearTimeout(this.timeout)
      this.save()
    }
  }

  closeBackground(event) {
    if (event.target === this.overlayTarget) this.close(event)
  }

  closeWithEscape(event) {
    if (event.key !== "Escape") return
    if (!this.hasModalTarget || this.modalTarget.classList.contains("hidden")) return

    this.close(event)
  }

  queueSave() {
    this.pending = true
    this.setStatus("Modifications en attente", "adm-tone-warning")
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.save(), SAVE_DELAY)
  }

  save(event) {
    if (event) event.preventDefault()
    if (this.isSaving) return

    this.isSaving = true
    this.setStatus("Enregistrement…", "adm-tone-water")

    const formData = new FormData(this.formTarget)

    fetch(this.urlValue, {
      method: "PATCH",
      headers: { Accept: "application/json" },
      body: formData
    })
      .then((response) => {
        if (!response.ok) throw new Error("save_failed")
        return response.json()
      })
      .then(() => {
        this.pending = false
        this.setStatus("Note enregistrée", "adm-tone-success")
        this.refreshSummary()
      })
      .catch(() => {
        this.setStatus("Erreur lors de l’enregistrement", "adm-tone-danger")
      })
      .finally(() => {
        this.isSaving = false
      })
  }

  // Remet le bandeau à jour sans recharger la page — sinon l'aperçu resterait
  // sur l'ancienne consigne jusqu'au prochain chargement, exactement le trou
  // que la mise en modale risquait d'ouvrir.
  refreshSummary() {
    const text = this.editor ? this.editor.innerText.replace(/\s+/g, " ").trim() : ""
    const filled = text.length > 0

    if (this.hasChipTarget) {
      this.chipTarget.textContent = filled ? "Consigne active" : "Aucune consigne"
      this.chipTarget.classList.toggle("adm-chip-accent", filled)
      this.chipTarget.classList.toggle("adm-chip-neutral", !filled)
    }

    if (this.hasPreviewTarget) this.previewTarget.textContent = text
    if (this.hasPlaceholderTarget) this.placeholderTarget.classList.toggle("hidden", filled)
  }

  get editor() {
    return this.element.querySelector("trix-editor")
  }

  // `toneClass` est une tonalité de l'admin (`adm-tone-*`), pas une couleur :
  // c'est `.adm-tonetext` qui va y chercher son `color`.
  setStatus(text, toneClass) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.className =
      "adm-tonetext text-xs font-medium transition-colors duration-200 " + toneClass
  }
}
