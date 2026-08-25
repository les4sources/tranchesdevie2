import { Controller } from "@hotwired/stimulus"

// Somme vivante des quatre ratios de panification. Depuis la décision des
// boulangers (25/08/2026), farine, eau, sel et levain sont tous des fractions
// de la pâte : leur somme doit tourner autour de 100 % de la pâte. L'écart au
// dessus est la marge de pétrissage, en dessous c'est une recette qui manquera
// de matière — d'où l'alerte visuelle plutôt qu'une validation bloquante.
export default class extends Controller {
  static targets = ["ratio", "sum", "hint"]

  connect() {
    this.recompute()
  }

  recompute() {
    const total = this.ratioTargets.reduce((acc, input) => {
      const value = parseFloat(String(input.value).replace(",", "."))
      return acc + (Number.isFinite(value) ? value : 0)
    }, 0)

    const percent = total * 100
    this.sumTarget.textContent = `${percent.toFixed(1).replace(".", ",")} %`

    const margin = percent - 100
    if (Math.abs(margin) < 0.05) {
      this.sumTarget.style.color = "#047857"
      this.hintTarget.textContent = "La recette boucle exactement."
    } else if (margin > 0) {
      this.sumTarget.style.color = margin > 10 ? "#b45309" : "#047857"
      this.hintTarget.textContent =
        `Marge de pétrissage : +${margin.toFixed(1).replace(".", ",")} % de matière au-delà du poids de pâte annoncé.`
    } else {
      this.sumTarget.style.color = "#b91c1c"
      this.hintTarget.textContent =
        `Manque ${Math.abs(margin).toFixed(1).replace(".", ",")} % de matière pour atteindre le poids de pâte annoncé.`
    }
  }
}
