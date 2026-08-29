import { Controller } from "@hotwired/stimulus"

// Calculateur de fournées (#194). Un clic sur un bouton de fournée écrit tout
// de suite en base et remplace le planificateur par le Turbo Stream renvoyé :
// les totaux se recalculent sous les yeux, sans rechargement ni bouton
// « Enregistrer ». Les boulangers ont les mains dans la farine.
//
// `userHasActed` vit au niveau du module, pas de l'instance : l'élément est
// remplacé à chaque réponse, donc une valeur d'instance serait perdue et la
// célébration se déclencherait au simple chargement d'une page déjà répartie.
let userHasActed = false

const CONFETTI_COLORS = ["#6B7E52", "#C2511F", "#C0871F", "#5C7A8C", "#82966A"]

export default class extends Controller {
  static targets = ["status"]
  static values = {
    url: String,
    complete: String
  }

  connect() {
    if (userHasActed && this.completeValue === "true") this.celebrate()
  }

  assign(event) {
    event.preventDefault()
    const button = event.currentTarget
    const { batchId, scope, scopeId } = button.dataset
    if (!scope || !scopeId) return

    userHasActed = true
    this.element.dataset.batchPlannerBusy = "true"
    this.setStatus("Affectation…")

    const body = new URLSearchParams()
    body.append("batch_id", batchId || "")
    body.append(scope, scopeId)

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        Accept: "text/vnd.turbo-stream.html",
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": this.csrfToken
      },
      body: body.toString()
    })
      .then((response) => {
        if (!response.ok) throw new Error("assign_failed")
        return response.text()
      })
      .then((html) => {
        // Le flux remplace `#batch-planner` : ce contrôleur est démonté ici,
        // et c'est le `connect()` du nouveau qui reprend la main.
        window.Turbo.renderStreamMessage(html)
      })
      .catch(() => {
        this.element.dataset.batchPlannerBusy = "false"
        this.setStatus("Erreur — l’affectation n’a pas été enregistrée.", "adm-tone-danger")
      })
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  setStatus(text, toneClass = "adm-tone-water") {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.className = `adm-tonetext text-xs font-medium ${toneClass}`
  }

  // Une note de jeu, jamais au prix de la lisibilité : douze bouts de papier
  // qui tombent une fois, et le lecteur qui préfère le calme n'en voit aucun
  // (`prefers-reduced-motion` les masque en CSS).
  celebrate() {
    const anchor = this.element.getBoundingClientRect()
    const originX = anchor.left + anchor.width / 2
    const originY = Math.max(anchor.top, 80)

    for (let i = 0; i < 12; i++) {
      const piece = document.createElement("span")
      piece.className = "adm-confetti"
      piece.style.background = CONFETTI_COLORS[i % CONFETTI_COLORS.length]
      piece.style.left = `${originX + (i - 6) * 14}px`
      piece.style.top = `${originY}px`
      piece.style.setProperty("--dx", `${(i - 6) * 10}px`)
      piece.style.setProperty("--dy", `${160 + (i % 4) * 40}px`)
      piece.style.setProperty("--rot", `${180 + i * 40}deg`)
      piece.addEventListener("animationend", () => piece.remove())
      document.body.appendChild(piece)
    }
  }
}
