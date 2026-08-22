import { Controller } from "@hotwired/stimulus"

// Pré-remplit « Date limite de commande » (cut_off_at) à la veille du jour de
// cuisson, à 16h00, dès que la date de cuisson est saisie.
//
// On ne remplit que si le champ est vide OU s'il contient encore la dernière
// valeur qu'on a auto-calculée : jamais une saisie manuelle. En édition, la
// valeur préexistante est considérée comme manuelle et n'est jamais écrasée.
export default class extends Controller {
  static targets = ["bakedOn", "cutOff"]

  connect() {
    // Sentinelle : toute valeur déjà présente au chargement est « manuelle ».
    this.lastAutofill = ""
  }

  fill() {
    if (!this.hasBakedOnTarget || !this.hasCutOffTarget) return

    const bakedOn = this.bakedOnTarget.value
    if (!bakedOn) return

    const current = this.cutOffTarget.value
    if (current && current !== this.lastAutofill) return // saisie manuelle : on n'y touche pas

    const [year, month, day] = bakedOn.split("-").map(Number)
    if (!year || !month || !day) return

    const eve = new Date(year, month - 1, day)
    eve.setDate(eve.getDate() - 1) // la veille

    const yyyy = eve.getFullYear()
    const mm = String(eve.getMonth() + 1).padStart(2, "0")
    const dd = String(eve.getDate()).padStart(2, "0")
    const value = `${yyyy}-${mm}-${dd}T16:00`

    this.cutOffTarget.value = value
    this.lastAutofill = value
  }
}
