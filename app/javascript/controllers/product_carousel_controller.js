import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="product-carousel"
export default class extends Controller {
  static targets = ["slide", "dot", "thumbnail"]
  static values = { currentIndex: { type: Number, default: 0 } }

  connect() {
    this.showSlide(this.currentIndexValue)
    
    // Initialize touch tracking
    this.touchStartX = null
    this.touchStartY = null
    this.minSwipeDistance = 50 // Minimum distance in pixels to trigger a swipe
  }

  disconnect() {
    // Cleanup if needed
  }

  showSlide(index) {
    if (index < 0) {
      index = this.slideTargets.length - 1
    } else if (index >= this.slideTargets.length) {
      index = 0
    }

    this.slideTargets.forEach((slide, i) => {
      slide.style.opacity = i === index ? "1" : "0"
    })

    this.dotTargets.forEach((dot, i) => {
      if (i === index) {
        dot.classList.add("bg-white")
        dot.classList.remove("bg-white/60")
      } else {
        dot.classList.remove("bg-white")
        dot.classList.add("bg-white/60")
      }
    })

    // Update thumbnails if they exist
    if (this.hasThumbnailTarget) {
      this.thumbnailTargets.forEach((thumbnail, i) => {
        if (i === index) {
          thumbnail.classList.add("ring-2", "ring-terracotta")
          thumbnail.classList.remove("ring-0")
        } else {
          thumbnail.classList.remove("ring-2", "ring-terracotta")
          thumbnail.classList.add("ring-0")
        }
      })
    }

    this.currentIndexValue = index
  }

  next() {
    this.showSlide(this.currentIndexValue + 1)
  }

  previous() {
    this.showSlide(this.currentIndexValue - 1)
  }

  goToSlide(event) {
    event.stopPropagation()
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.carouselIndex)
    this.showSlide(index)
  }

  stopPropagation(event) {
    // Stop propagation for carousel container clicks to prevent navigation
    if (event.target.closest('button')) {
      event.stopPropagation()
    }
  }

  // Touch event handlers for swipe detection
  touchStart(event) {
    const touch = event.touches[0]
    this.touchStartX = touch.clientX
    this.touchStartY = touch.clientY
  }

  touchMove(event) {
    // Prevent default scrolling while swiping horizontally
    if (this.touchStartX !== null) {
      const touch = event.touches[0]
      const deltaX = Math.abs(touch.clientX - this.touchStartX)
      const deltaY = Math.abs(touch.clientY - this.touchStartY)
      
      // If horizontal swipe is more significant than vertical, prevent scrolling
      // Only prevent if we've moved enough horizontally to indicate a swipe intent
      if (deltaX > 10 && deltaX > deltaY) {
        event.preventDefault()
      }
    }
  }

  touchEnd(event) {
    if (this.touchStartX === null) return

    const touch = event.changedTouches[0]
    const deltaX = touch.clientX - this.touchStartX
    const deltaY = touch.clientY - this.touchStartY
    const absDeltaX = Math.abs(deltaX)
    const absDeltaY = Math.abs(deltaY)

    // Only process swipe if horizontal movement is greater than vertical
    if (absDeltaX > absDeltaY && absDeltaX > this.minSwipeDistance) {
      if (deltaX > 0) {
        // Swipe right - go to previous slide
        this.previous()
      } else {
        // Swipe left - go to next slide
        this.next()
      }
    }

    // Reset touch tracking
    this.touchStartX = null
    this.touchStartY = null
  }
}

