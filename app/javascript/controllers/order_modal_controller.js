import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay", "content", "body", "title", "modal"]
  static values = {
    orderId: Number,
    orderData: Object
  }

  connect() {
    // Trouver la modale dans le scope du contrôleur
    if (this.hasModalTarget) {
      this.modal = this.modalTarget
    } else {
      // Fallback: chercher dans le DOM
      this.modal = this.element.querySelector('#order-modal') || document.getElementById('order-modal')
    }
    
    if (!this.modal) {
      console.error('Order modal element not found')
    }
  }

  open(event) {
    event.preventDefault()
    event.stopPropagation()
    
    if (!this.modal) {
      console.error('Modal not found')
      return
    }
    
    const orderData = JSON.parse(event.currentTarget.dataset.orderModalOrderDataValue)
    const orderId = event.currentTarget.dataset.orderModalOrderIdValue
    
    this.orderIdValue = parseInt(orderId)
    this.orderDataValue = orderData
    
    // Rendre le contenu avant d'afficher la modale
    this.renderOrderDetails(orderData)
    
    // Vérifier que les targets existent
    if (!this.hasBodyTarget || !this.hasTitleTarget) {
      console.error('Modal targets not found', {
        hasBodyTarget: this.hasBodyTarget,
        hasTitleTarget: this.hasTitleTarget,
        modal: this.modal
      })
      return
    }
    
    this.modal.classList.remove('hidden')
    document.body.style.overflow = 'hidden'
  }

  close() {
    this.modal.classList.add('hidden')
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

  async cancelOrder() {
    if (!confirm('Êtes-vous sûr de vouloir annuler cette commande ? Cette action est irréversible.')) {
      return
    }

    try {
      const response = await fetch(`/customers/mon-compte/commandes/${this.orderIdValue}`, {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'text/html'
        }
      })

      if (response.redirected) {
        window.location.href = response.url
      } else {
        const html = await response.text()
        const parser = new DOMParser()
        const doc = parser.parseFromString(html, 'text/html')
        
        const alertElement = doc.querySelector('.alert')
        if (alertElement) {
          alert(alertElement.textContent.trim())
        } else {
          window.location.reload()
        }
      }
    } catch (error) {
      alert('Erreur lors de l\'annulation de la commande')
    }
  }

  renderOrderDetails(order) {
    const bakeDay = order.bake_day
    const orderItems = order.order_items || []
    // Vérifier si le cut_off est passé en comparant avec l'heure actuelle
    const cutOffAt = bakeDay.cut_off_at ? new Date(bakeDay.cut_off_at) : null
    const now = new Date()
    const canCancel = cutOffAt && now < cutOffAt && (order.status === 'paid' || order.status === 'unpaid')

    // Calculer le sous-total à partir des order_items
    const subtotalCents = orderItems.reduce((sum, item) => {
      return sum + (item.qty * item.unit_price_cents)
    }, 0)

    // Calculer la remise si le client a un groupe avec discount_percent
    const customer = order.customer
    const discountPercent = customer?.group?.discount_percent || 0
    const discountCents = discountPercent > 0 
      ? Math.round(subtotalCents * discountPercent / 100)
      : 0

    // Déterminer la couleur du statut
    const statusColors = {
      'pending': 'bg-yellow-100 text-yellow-800',
      'paid': 'bg-blue-100 text-blue-800',
      'ready': 'bg-green-100 text-green-800',
      'picked_up': 'bg-gray-100 text-gray-800',
      'no_show': 'bg-red-100 text-red-800',
      'cancelled': 'bg-red-100 text-red-800'
    }

    const statusLabels = {
      'pending': 'En attente',
      'unpaid': 'Non payée',
      'paid': 'Payée',
      'ready': 'Prête',
      'picked_up': 'Récupérée',
      'no_show': 'Non reçue',
      'cancelled': 'Annulée'
    }

    const statusColor = statusColors[order.status] || 'bg-gray-100 text-gray-800'
    const statusLabel = statusLabels[order.status] || order.status

    const html = `
      <div class="space-y-4">
        <div>
          <h4 class="text-sm font-medium text-gray-500 mb-1">Numéro de commande</h4>
          <p class="text-gray-900">${order.order_number}</p>
        </div>

        <div>
          <h4 class="text-sm font-medium text-gray-500 mb-1">Statut</h4>
          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${statusColor}">
            ${statusLabel}
          </span>
        </div>

        <div>
          <h4 class="text-sm font-medium text-gray-500 mb-1">Jour de cuisson</h4>
          <p class="text-gray-900">${new Date(bakeDay.baked_on).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric' })}</p>
        </div>

        <div>
          <h4 class="text-sm font-medium text-gray-500 mb-2">Articles</h4>
          <div class="space-y-2">
            ${orderItems.map(item => {
              const variant = item.product_variant
              const product = variant.product
              const unitPrice = (item.unit_price_cents / 100).toFixed(2)
              const subtotal = (item.qty * item.unit_price_cents / 100).toFixed(2)
              return `
                <div class="flex justify-between items-start py-2 border-b border-gray-200">
                  <div>
                    <p class="font-medium text-gray-900">${product.name}</p>
                    <p class="text-sm text-gray-600">${variant.name}</p>
                  </div>
                  <div class="text-right">
                    <p class="text-sm text-gray-600">${item.qty} x ${unitPrice}€</p>
                    <p class="font-medium text-gray-900">${subtotal}€</p>
                  </div>
                </div>
              `
            }).join('')}
          </div>
        </div>

        <div class="pt-4 border-t border-gray-200 space-y-2">
          <div class="flex justify-between items-center">
            <span class="text-sm text-gray-600">Sous-total</span>
            <span class="text-sm text-gray-900">
              ${(subtotalCents / 100).toFixed(2)}€
            </span>
          </div>
          ${discountCents > 0 ? `
            <div class="flex justify-between items-center">
              <span class="text-sm text-gray-600">Remise (${discountPercent}%)</span>
              <span class="text-sm text-green-600 font-medium">
                -${(discountCents / 100).toFixed(2)}€
              </span>
            </div>
          ` : ''}
          <div class="flex justify-between items-center pt-2 border-t border-gray-200">
            <span class="text-lg font-medium text-gray-900">Total</span>
            <span class="text-xl font-bold text-gray-900">
              ${(order.total_cents / 100).toFixed(2)}€
            </span>
          </div>
        </div>

        ${canCancel ? `
          <div class="pt-4 border-t border-gray-200">
            <button 
              type="button"
              data-action="click->order-modal#cancelOrder"
              class="w-full px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500">
              Annuler la commande
            </button>
          </div>
        ` : ''}
      </div>
    `

    this.bodyTarget.innerHTML = html
    this.titleTarget.textContent = `Commande ${order.order_number}`
  }
}

