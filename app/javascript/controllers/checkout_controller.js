import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async sendOTP(event) {
    event.preventDefault()
    
    const phoneInput = document.getElementById('customer_phone_e164')
    const phone = phoneInput?.value
    if (!phone) {
      this.showMessage('Veuillez entrer un numéro de téléphone', 'error')
      return
    }

    const sendOtpBtn = document.getElementById('send-otp-btn')
    if (sendOtpBtn) {
      sendOtpBtn.disabled = true
      sendOtpBtn.textContent = 'Envoi...'
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
        this.showMessage('Le code t\'a été envoyé par SMS', 'success')
      } else {
        this.showMessage(data.error || 'Erreur lors de l\'envoi', 'error')
      }
    } catch (error) {
      this.showMessage('Erreur de connexion', 'error')
    } finally {
      const sendOtpBtn = document.getElementById('send-otp-btn')
      if (sendOtpBtn) {
        sendOtpBtn.disabled = false
        sendOtpBtn.textContent = 'Envoyer le code de vérification'
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

    const verifyOtpBtn = document.getElementById('verify-otp-btn')
    if (verifyOtpBtn) {
      verifyOtpBtn.disabled = true
      verifyOtpBtn.textContent = 'Vérification...'
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
      const verifyOtpBtn = document.getElementById('verify-otp-btn')
      if (verifyOtpBtn) {
        verifyOtpBtn.disabled = false
        verifyOtpBtn.textContent = 'Vérifier le code'
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

