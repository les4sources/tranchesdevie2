import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "overlay", "body", "form", "error"]

  connect() {
    // La modale est dans le document, pas nécessairement dans le scope du contrôleur
    // On la trouvera lors de l'ouverture
  }

  open(event) {
    event.preventDefault()
    event.stopPropagation()
    
    // Trouver la modale dans le document
    this.modal = document.getElementById('sms-modal')
    
    if (!this.modal) {
      console.error('SMS modal element not found')
      return
    }
    
    // Réinitialiser le formulaire
    if (this.hasFormTarget) {
      this.formTarget.reset()
    }
    
    // Réinitialiser les erreurs
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = ''
      this.errorTarget.classList.add('hidden')
    }
    
    this.modal.classList.remove('hidden')
    document.body.style.overflow = 'hidden'
    
    // Focus sur le champ de texte
    const textarea = this.modal.querySelector('textarea')
    if (textarea) {
      setTimeout(() => textarea.focus(), 100)
    }
  }

  close() {
    if (this.modal) {
      this.modal.classList.add('hidden')
    }
    document.body.style.overflow = ''
  }

  closeBackground(event) {
    if (event.target === this.overlayTarget) {
      this.close()
    }
  }

  closeWithEscape(event) {
    if (event.key === 'Escape') {
      this.close()
    }
  }

  async submit(event) {
    event.preventDefault()
    
    const formData = new FormData(this.formTarget)
    const body = formData.get('body')
    
    if (!body || body.trim().length === 0) {
      this.showError('Le message ne peut pas être vide')
      return
    }
    
    const submitButton = this.formTarget.querySelector('button[type="submit"]')
    const originalText = submitButton.textContent
    submitButton.disabled = true
    submitButton.textContent = 'Envoi...'
    
    try {
      const response = await fetch(this.formTarget.action, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'application/json'
        },
        body: formData
      })
      
      const data = await response.json()
      
      if (data.success) {
        // Fermer la modale et recharger la page pour afficher le nouveau SMS
        this.close()
        window.location.reload()
      } else {
        this.showError(data.error || 'Erreur lors de l\'envoi du SMS')
        submitButton.disabled = false
        submitButton.textContent = originalText
      }
    } catch (error) {
      console.error('Error sending SMS:', error)
      this.showError('Erreur de connexion')
      submitButton.disabled = false
      submitButton.textContent = originalText
    }
  }

  showError(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.classList.remove('hidden')
    } else {
      alert(message)
    }
  }
}

