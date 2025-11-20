import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["phoneInput", "otpInput"]

  async sendOTP(event) {
    event.preventDefault()
    
    const phone = this.phoneInputTarget?.value
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
      const formData = new FormData()
      formData.append('phone_e164', phone)

      const response = await fetch('/connexion', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: formData
      })

      const html = await response.text()
      const parser = new DOMParser()
      const doc = parser.parseFromString(html, 'text/html')

      // Vérifier s'il y a des erreurs
      const alertElement = doc.querySelector('.alert, [class*="alert"]')
      if (alertElement) {
        this.showMessage(alertElement.textContent.trim(), 'error')
        if (sendOtpBtn) {
          sendOtpBtn.disabled = false
          sendOtpBtn.textContent = 'Me connecter'
        }
        return
      }

      // Vérifier si le formulaire OTP est maintenant visible
      const otpSection = document.getElementById('otp-input-section')
      if (otpSection) {
        otpSection.classList.remove('hidden')
      }

      // Afficher le message de succès
      const noticeElement = doc.querySelector('.notice, [class*="notice"]')
      if (noticeElement) {
        this.showMessage(noticeElement.textContent.trim(), 'success')
      } else {
        this.showMessage('Code envoyé par SMS', 'success')
      }
    } catch (error) {
      this.showMessage('Erreur de connexion', 'error')
    } finally {
      if (sendOtpBtn) {
        sendOtpBtn.disabled = false
        sendOtpBtn.textContent = 'Me connecter'
      }
    }
  }

  async verifyOTP(event) {
    event.preventDefault()

    const code = this.otpInputTarget?.value
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
      const formData = new FormData()
      formData.append('phone_e164', this.phoneInputTarget.value)
      formData.append('otp_code', code)

      const response = await fetch('/connexion', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: formData
      })

      if (response.redirected) {
        window.location.href = response.url
      } else {
        const html = await response.text()
        const parser = new DOMParser()
        const doc = parser.parseFromString(html, 'text/html')

        const alertElement = doc.querySelector('.alert, [class*="alert"]')
        if (alertElement) {
          this.showMessage(alertElement.textContent.trim(), 'error')
        } else {
          this.showMessage('Erreur lors de la vérification', 'error')
        }
      }
    } catch (error) {
      this.showMessage('Erreur de connexion', 'error')
    } finally {
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

