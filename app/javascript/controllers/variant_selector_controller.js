import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="variant-selector"
export default class extends Controller {
  static targets = ["option", "variantInput"]

  connect() {
    // Initialize selected variant
    const checkedOption = this.optionTargets.find(option => {
      const radio = option.querySelector('input[type="radio"]')
      return radio && radio.checked
    })
    if (checkedOption) {
      this.selectVariant(checkedOption)
    }
  }

  select(event) {
    const option = event.currentTarget
    this.selectVariant(option)
  }

  selectVariant(option) {
    // Remove selected state from all options
    this.optionTargets.forEach(opt => {
      opt.classList.remove('border-green-500', 'bg-green-50')
      opt.classList.add('border-gray-300')
      
      // Remove green border from the absolute border element
      const absoluteBorders = opt.querySelectorAll('.absolute')
      absoluteBorders.forEach(border => {
        if (border.classList.contains('-inset-px') || border.classList.contains('border-2')) {
          border.classList.remove('border-green-500')
        }
      })
      
      const checkIcons = opt.querySelectorAll('.material-symbols-outlined')
      checkIcons.forEach(icon => {
        // Only remove check icons, not help icons
        if (icon.textContent === 'check_circle') {
          icon.remove()
        }
      })
    })

    // Add selected state to clicked option
    option.classList.remove('border-gray-300')
    option.classList.add('border-green-500', 'bg-green-50')
    
    // Add green border to the absolute border element
    const absoluteBorders = option.querySelectorAll('.absolute')
    absoluteBorders.forEach(border => {
      if (border.classList.contains('-inset-px') || border.classList.contains('border-2')) {
        border.classList.add('border-green-500')
      }
    })
    
    // Add check icon
    const checkIcon = document.createElement('span')
    checkIcon.className = 'material-symbols-outlined text-green-600 absolute top-4 right-4'
    checkIcon.textContent = 'check_circle'
    option.appendChild(checkIcon)

    // Update radio button
    const radio = option.querySelector('input[type="radio"]')
    if (radio) {
      radio.checked = true
    }

    // Update hidden input for form
    const variantId = option.dataset.variantId
    if (variantId && this.hasVariantInputTarget) {
      this.variantInputTarget.value = variantId
    }

    // Update price display (if exists)
    const price = option.dataset.variantPrice
    if (price) {
      const priceElement = document.querySelector('[data-price-display]')
      if (priceElement) {
        const formattedPrice = parseFloat(price).toFixed(2).replace('.', ',')
        priceElement.textContent = `${formattedPrice} €`
      }
    }
  }
}

