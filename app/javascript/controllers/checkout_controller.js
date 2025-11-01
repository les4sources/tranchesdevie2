import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["phoneInput", "otpInput", "otpSection", "message", "sendOtpBtn", "verifyOtpBtn"]

  connect() {
    this.phoneInputTarget = document.getElementById('customer_phone_e164') || this.phoneInputTarget
  }

  async sendOTP(event) {
    event.preventDefault()
    
    const phone = this.phoneInputTarget?.value || document.getElementById('customer_phone_e164')?.value
    if (!phone) {
      this.showMessage('Veuillez entrer un numéro de téléphone', 'error')
      return
    }

    if (this.sendOtpBtnTarget) {
      this.sendOtpBtnTarget.disabled = true
      this.sendOtpBtnTarget.textContent = 'Envoi...'
    }

    try {
      const response = await fetch('/checkout/verify_phone', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ phone_e164: phone })
      })

      const data = await response.json()

      if (data.success) {
        const otpSection = document.getElementById('otp-input-section')
        if (otpSection) {
          otpSection.classList.remove('hidden')
        }
        this.showMessage('Code envoyé par SMS', 'success')
      } else {
        this.showMessage(data.error || 'Erreur lors de l\'envoi', 'error')
      }
    } catch (error) {
      this.showMessage('Erreur de connexion', 'error')
    } finally {
      if (this.sendOtpBtnTarget) {
        this.sendOtpBtnTarget.disabled = false
        this.sendOtpBtnTarget.textContent = 'Envoyer le code de vérification'
      }
    }
  }

  async verifyOTP(event) {
    event.preventDefault()

    const code = document.getElementById('otp_code')?.value
    if (!code || code.length !== 6) {
      this.showMessage('Veuillez entrer un code à 6 chiffres', 'error')
      return
    }

    if (this.verifyOtpBtnTarget) {
      this.verifyOtpBtnTarget.disabled = true
      this.verifyOtpBtnTarget.textContent = 'Vérification...'
    }

    try {
      const response = await fetch('/checkout/verify_otp', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ code: code })
      })

      const data = await response.json()

      if (data.success) {
        this.showMessage('Code vérifié ! Redirection...', 'success')
        setTimeout(() => {
          window.location.reload()
        }, 1000)
      } else {
        this.showMessage(data.error || 'Code incorrect', 'error')
      }
    } catch (error) {
      this.showMessage('Erreur de connexion', 'error')
    } finally {
      if (this.verifyOtpBtnTarget) {
        this.verifyOtpBtnTarget.disabled = false
        this.verifyOtpBtnTarget.textContent = 'Vérifier le code'
      }
    }
  }

  showMessage(message, type) {
    const messageEl = document.getElementById('otp-message')
    if (messageEl) {
      messageEl.textContent = message
      messageEl.className = type === 'success' ? 'mt-4 text-sm text-green-600' : 'mt-4 text-sm text-red-600'
      messageEl.classList.remove('hidden')
    }
  }
}

