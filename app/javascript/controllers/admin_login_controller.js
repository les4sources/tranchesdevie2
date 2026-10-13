import { Controller } from "@hotwired/stimulus"

// Page de connexion admin (deux variantes : « fournil » et « braise »).
// - toggle : affiche / masque le mot de passe
// - stoke  : chaque caractère tapé attise le feu (variable CSS --heat, 0 → 1)
//            et fait monter le thermomètre de 180 à 260 °C
// - braises : particules dessinées sur un canvas, qui montent de la bouche du
//            four et dérivent avec la souris ; coupées si l'utilisateur
//            préfère réduire les animations.
export default class extends Controller {
  static targets = ["input", "eye", "button", "canvas", "temperature"]
  static values = { heat: Boolean }

  connect() {
    this.heat = 0
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    if (this.heatValue) this.applyHeat()
    if (this.hasCanvasTarget && !this.reduced) this.startEmbers()
  }

  disconnect() {
    cancelAnimationFrame(this.frame)
    window.removeEventListener("resize", this.resize)
    window.removeEventListener("pointermove", this.pointer)
  }

  toggle() {
    const shown = this.inputTarget.type === "text"
    this.inputTarget.type = shown ? "password" : "text"
    this.eyeTarget.setAttribute("aria-label", shown ? "Afficher le mot de passe" : "Masquer le mot de passe")
    this.eyeTarget.classList.toggle("is-on", !shown)
    this.inputTarget.focus()
  }

  stoke() {
    this.heat = Math.min(this.inputTarget.value.length / 12, 1)
    this.applyHeat()
    this.burst(4)
  }

  submit() {
    this.element.classList.add("is-submitting")
    if (this.heatValue) {
      this.heat = 1
      this.applyHeat()
      this.burst(60)
    }
  }

  applyHeat() {
    this.element.style.setProperty("--heat", this.heat.toFixed(3))
    if (this.hasTemperatureTarget) {
      this.temperatureTarget.textContent = Math.round(180 + this.heat * 80)
    }
  }

  // ── Braises ────────────────────────────────────────────────────────────
  startEmbers() {
    const canvas = this.canvasTarget
    this.ctx = canvas.getContext("2d")
    this.particles = []
    this.wind = 0

    this.resize = () => {
      const dpr = Math.min(window.devicePixelRatio || 1, 2)
      canvas.width = canvas.clientWidth * dpr
      canvas.height = canvas.clientHeight * dpr
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
      this.w = canvas.clientWidth
      this.h = canvas.clientHeight
    }
    this.pointer = (e) => { this.wind = (e.clientX / window.innerWidth - 0.5) * 0.8 }

    this.resize()
    window.addEventListener("resize", this.resize)
    window.addEventListener("pointermove", this.pointer)

    for (let i = 0; i < 90; i++) this.particles.push(this.spawn(true))
    const tick = () => {
      this.draw()
      this.frame = requestAnimationFrame(tick)
    }
    tick()
  }

  spawn(anywhere = false) {
    const spread = this.w * (0.28 + this.heat * 0.2)
    return {
      x: this.w / 2 + (Math.random() - 0.5) * spread * 2,
      y: anywhere ? Math.random() * this.h : this.h + 10,
      r: 0.6 + Math.random() * 2.2,
      vy: 0.35 + Math.random() * 1.1,
      vx: (Math.random() - 0.5) * 0.3,
      life: 0,
      max: 260 + Math.random() * 420,
      phase: Math.random() * Math.PI * 2
    }
  }

  burst(count) {
    if (!this.particles) return
    for (let i = 0; i < count; i++) {
      const p = this.spawn()
      p.y = this.h * (0.8 + Math.random() * 0.2)
      p.vy *= 2.2
      this.particles.push(p)
    }
  }

  draw() {
    const { ctx, w, h } = this
    ctx.clearRect(0, 0, w, h)
    ctx.globalCompositeOperation = "lighter"
    const boost = 1 + this.heat * 1.4

    this.particles = this.particles.filter((p) => {
      p.life++
      p.phase += 0.04
      p.x += p.vx + Math.sin(p.phase) * 0.35 + this.wind
      p.y -= p.vy * boost
      const t = p.life / p.max
      if (t >= 1 || p.y < -20) return false

      const alpha = Math.sin(Math.PI * t) * (0.55 + 0.45 * Math.sin(p.phase * 3))
      const g = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.r * 5)
      g.addColorStop(0, `rgba(255, 214, 140, ${alpha})`)
      g.addColorStop(0.35, `rgba(240, 120, 40, ${alpha * 0.55})`)
      g.addColorStop(1, "rgba(160, 40, 10, 0)")
      ctx.fillStyle = g
      ctx.beginPath()
      ctx.arc(p.x, p.y, p.r * 5, 0, Math.PI * 2)
      ctx.fill()
      return true
    })

    const target = 90 + Math.round(this.heat * 110)
    while (this.particles.length < target) this.particles.push(this.spawn())
  }
}
