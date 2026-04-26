// Skribbl 캔버스 — drawer 가 그리고 다른 사람들 보는 그림판.
//
// 책임:
//   1. drawer 일 때만 mousedown/move/up + touch 이벤트로 stroke 발생.
//   2. stroke 마다 server 에 phx-event "skribbl_stroke" push (sanitize 됨).
//   3. server 가 다른 player 에게 broadcast → 모든 client 가 push_event
//      "skribbl:stroke" 받아 canvas 에 line draw.
//   4. "skribbl:clear" → 화면 clear.
//   5. "skribbl:strokes_replay" → 늦게 join 한 사람이 현재까지의 strokes 전부 다시 그림.
//
// 좌표는 canvas 의 logical 0..width 좌표 — server 에서 sanitize 시 0..2000 범위.

const COLORS = ["#000000", "#ff4444", "#4488ff", "#44cc44", "#ffaa22", "#aa55ff", "#ffffff"]
const SIZES = [2, 4, 8, 14]

export const SkribblCanvas = {
  mounted() {
    this.canvas = this.el
    this.ctx = this.canvas.getContext("2d")
    this.parseDataset()
    this.lastPoint = null
    this.dragging = false
    this.currentColor = COLORS[0]
    this.currentSize = SIZES[1]

    this._down = (e) => this.onPointerDown(e)
    this._move = (e) => this.onPointerMove(e)
    this._up = (e) => this.onPointerUp(e)

    this.canvas.addEventListener("pointerdown", this._down)
    this.canvas.addEventListener("pointermove", this._move)
    window.addEventListener("pointerup", this._up)
    this.canvas.addEventListener("pointerleave", this._up)

    this.handleEvent("skribbl:stroke", (s) => this.drawStroke(s))
    this.handleEvent("skribbl:clear", () => this.clearCanvas())
    this.handleEvent("skribbl:strokes_replay", ({ strokes }) => {
      this.clearCanvas()
      ;(strokes || []).forEach((s) => this.drawStroke(s))
    })

    this.bindToolButtons()
    this.clearCanvas()
  },

  updated() {
    this.parseDataset()
  },

  destroyed() {
    this.canvas.removeEventListener("pointerdown", this._down)
    this.canvas.removeEventListener("pointermove", this._move)
    window.removeEventListener("pointerup", this._up)
    this.canvas.removeEventListener("pointerleave", this._up)
    if (this._toolClick) document.removeEventListener("click", this._toolClick)
  },

  parseDataset() {
    this.isDrawer = this.canvas.dataset.isDrawer === "true"
    this.canvas.style.cursor = this.isDrawer ? "crosshair" : "not-allowed"
  },

  bindToolButtons() {
    // Event delegation — LiveView 가 도구 버튼들을 re-render 해도 listener 유지.
    // 버튼 자체에 직접 binding 하면 mount 시점에 없거나 DOM 교체 후 잃음.
    this._toolClick = (e) => {
      const colorBtn = e.target.closest("[data-skribbl-color]")
      if (colorBtn) {
        this.currentColor = colorBtn.dataset.skribblColor
        this.highlightTool("color", this.currentColor)
        return
      }
      const sizeBtn = e.target.closest("[data-skribbl-size]")
      if (sizeBtn) {
        this.currentSize = parseInt(sizeBtn.dataset.skribblSize, 10) || 4
        this.highlightTool("size", String(this.currentSize))
      }
    }
    document.addEventListener("click", this._toolClick)
  },

  highlightTool(kind, value) {
    const sel = kind === "color" ? "[data-skribbl-color]" : "[data-skribbl-size]"
    document.querySelectorAll(sel).forEach((b) => {
      const matches = b.dataset[kind === "color" ? "skribblColor" : "skribblSize"] === value
      b.classList.toggle("ring-2", matches)
      b.classList.toggle("ring-primary", matches)
    })
  },

  pointAt(e) {
    const rect = this.canvas.getBoundingClientRect()
    const scaleX = this.canvas.width / rect.width
    const scaleY = this.canvas.height / rect.height
    return {
      x: (e.clientX - rect.left) * scaleX,
      y: (e.clientY - rect.top) * scaleY,
    }
  },

  onPointerDown(e) {
    if (!this.isDrawer) return
    this.dragging = true
    this.lastPoint = this.pointAt(e)
    // 첫 클릭은 점 하나 — from == to.
    this.emitStroke(this.lastPoint, this.lastPoint)
  },

  onPointerMove(e) {
    if (!this.isDrawer || !this.dragging) return
    const p = this.pointAt(e)
    if (!this.lastPoint) {
      this.lastPoint = p
      return
    }
    this.emitStroke(this.lastPoint, p)
    this.lastPoint = p
  },

  onPointerUp(_e) {
    this.dragging = false
    this.lastPoint = null
  },

  emitStroke(from, to) {
    const stroke = {
      from: { x: Math.round(from.x), y: Math.round(from.y) },
      to: { x: Math.round(to.x), y: Math.round(to.y) },
      color: this.currentColor,
      size: this.currentSize,
    }
    // 로컬 즉시 반영 (latency 안 느끼게).
    this.drawStroke(stroke)
    this.pushEvent("skribbl_stroke", { stroke })
  },

  drawStroke(s) {
    if (!s || !s.from || !s.to) return
    this.ctx.strokeStyle = s.color || "#000000"
    this.ctx.lineWidth = s.size || 4
    this.ctx.lineCap = "round"
    this.ctx.beginPath()
    this.ctx.moveTo(s.from.x, s.from.y)
    this.ctx.lineTo(s.to.x, s.to.y)
    this.ctx.stroke()
  },

  clearCanvas() {
    this.ctx.fillStyle = "#ffffff"
    this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height)
  },
}
