import { Controller } from "@hotwired/stimulus"

// Modale native (<dialog>) : `showModal()` apporte le fond, le piège à focus
// et la fermeture par Échap sans code maison.
//
//   div data-controller="dialog"
//     button data-action="dialog#open"
//     dialog data-dialog-target="dialog" data-action="click->dialog#backdropClose"
//       button data-action="dialog#close"
export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    event?.preventDefault()
    this.dialogTarget.showModal()
    document.body.style.overflow = "hidden"
    this.dialogTarget.addEventListener("close", this.restoreScroll, { once: true })
  }

  close(event) {
    event?.preventDefault()
    this.dialogTarget.close()
  }

  // Un clic sur le fond (hors de la carte) ferme la modale. Le <dialog> occupe
  // tout l'écran : sa cible directe n'est lui-même que quand on clique dehors.
  backdropClose(event) {
    if (event.target === this.dialogTarget) this.dialogTarget.close()
  }

  restoreScroll = () => {
    document.body.style.overflow = ""
  }

  disconnect() {
    if (this.dialogTarget.open) this.dialogTarget.close()
    this.restoreScroll()
  }
}
