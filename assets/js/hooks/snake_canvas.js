// Snake.io 캔버스 렌더 훅 — server 가 보낸 snakes / food payload 그림.
// data-grid-size, data-snakes (json), data-food (json), data-me-id.
// phx-update="ignore" — DOM diff 안 함, dataset 변경시 updated() 호출 안 됨.
// 그래서 LiveView 쪽에서 push_event("snake:render", ...) 로 알리는 대신,
// MutationObserver 로 dataset 변경 감지.

function parsePayload(el) {
  let snakes = []
  let food = []
  let gridSize = 100
  try { snakes = JSON.parse(el.dataset.snakes || "[]") } catch (_) {}
  try { food = JSON.parse(el.dataset.food || "[]") } catch (_) {}
  try { gridSize = parseInt(el.dataset.gridSize || "100", 10) || 100 } catch (_) {}
  return { snakes, food, gridSize, meId: el.dataset.meId }
}

function render(canvas, payload) {
  const { snakes, food, gridSize, meId } = payload
  const ctx = canvas.getContext("2d")
  const w = canvas.width
  const h = canvas.height
  const cell = Math.floor(Math.min(w, h) / gridSize)

  // 배경.
  ctx.fillStyle = "#0f172a"
  ctx.fillRect(0, 0, w, h)

  // 격자 (10칸 마다 옅은 선).
  ctx.strokeStyle = "rgba(148, 163, 184, 0.06)"
  ctx.lineWidth = 1
  for (let i = 0; i <= gridSize; i += 10) {
    const x = i * cell + 0.5
    ctx.beginPath()
    ctx.moveTo(x, 0)
    ctx.lineTo(x, h)
    ctx.moveTo(0, x)
    ctx.lineTo(w, x)
    ctx.stroke()
  }

  // food.
  ctx.fillStyle = "#fde047"
  for (const [r, c] of food) {
    ctx.fillRect(c * cell + 1, r * cell + 1, cell - 2, cell - 2)
  }

  // snake 본체.
  for (const s of snakes) {
    if (!s.body || s.body.length === 0) continue
    const alpha = s.alive ? 1 : 0.25
    // 몸통.
    ctx.fillStyle = s.color || "#22c55e"
    ctx.globalAlpha = alpha
    for (let i = 1; i < s.body.length; i++) {
      const [r, c] = s.body[i]
      ctx.fillRect(c * cell, r * cell, cell, cell)
    }
    // head 강조 (밝게 + 본인이면 ring).
    const [hr, hc] = s.body[0]
    ctx.fillStyle = lighten(s.color || "#22c55e", 30)
    ctx.fillRect(hc * cell, hr * cell, cell, cell)
    if (s.is_me || s.id === meId) {
      ctx.globalAlpha = alpha
      ctx.strokeStyle = "#ffffff"
      ctx.lineWidth = 2
      ctx.strokeRect(hc * cell + 1, hr * cell + 1, cell - 2, cell - 2)
    }
    ctx.globalAlpha = 1
  }
}

// 간단 hex lighten — 색 RR GG BB 각각 +amount (cap 255).
function lighten(hex, amount) {
  if (!hex || hex[0] !== "#" || hex.length !== 7) return hex
  const r = Math.min(255, parseInt(hex.slice(1, 3), 16) + amount)
  const g = Math.min(255, parseInt(hex.slice(3, 5), 16) + amount)
  const b = Math.min(255, parseInt(hex.slice(5, 7), 16) + amount)
  return "#" + [r, g, b].map((v) => v.toString(16).padStart(2, "0")).join("")
}

export const SnakeCanvas = {
  mounted() {
    this.canvas = this.el.querySelector("canvas")
    if (this.canvas) render(this.canvas, parsePayload(this.el))
  },

  updated() {
    if (this.canvas) render(this.canvas, parsePayload(this.el))
  },
}
