// Pac-Man 캔버스 — 28×31 maze, server payload 그대로 그림.
// data-payload (json) — walls, dots, pellets, door, pacman, ghosts, frightened, tick_no.

const CELL = 20

const GHOST_COLORS = {
  blinky: "#ef4444",
  pinky: "#f9a8d4",
  inky: "#67e8f9",
  clyde: "#fb923c",
}

function parsePayload(el) {
  try {
    return JSON.parse(el.dataset.payload || "{}")
  } catch (_) {
    return null
  }
}

function render(ctx, p) {
  if (!p) return
  const w = ctx.canvas.width
  const h = ctx.canvas.height

  ctx.fillStyle = "#000000"
  ctx.fillRect(0, 0, w, h)

  // 벽 — 진한 파랑.
  ctx.fillStyle = "#1e3a8a"
  for (const [r, c] of p.walls || []) {
    ctx.fillRect(c * CELL, r * CELL, CELL, CELL)
  }
  // 벽 내부 라인 (작게) — 클래식 느낌.
  ctx.strokeStyle = "#3b82f6"
  ctx.lineWidth = 1
  for (const [r, c] of p.walls || []) {
    ctx.strokeRect(c * CELL + 2, r * CELL + 2, CELL - 4, CELL - 4)
  }

  // ghost 문 (분홍).
  if (p.door) {
    const [r, c] = p.door
    ctx.fillStyle = "#f9a8d4"
    ctx.fillRect(c * CELL, r * CELL + CELL / 2 - 2, CELL, 4)
  }

  // dots (작은 점).
  ctx.fillStyle = "#fde047"
  for (const [r, c] of p.dots || []) {
    ctx.beginPath()
    ctx.arc(c * CELL + CELL / 2, r * CELL + CELL / 2, 2, 0, Math.PI * 2)
    ctx.fill()
  }

  // power pellets (큰 점, blink).
  const blink = ((p.tick_no || 0) % 6) < 3
  if (blink) {
    ctx.fillStyle = "#fde047"
    for (const [r, c] of p.pellets || []) {
      ctx.beginPath()
      ctx.arc(c * CELL + CELL / 2, r * CELL + CELL / 2, 5, 0, Math.PI * 2)
      ctx.fill()
    }
  }

  // ghosts.
  for (const g of p.ghosts || []) {
    drawGhost(ctx, g, p.frightened, p.tick_no || 0)
  }

  // pac-man.
  drawPacman(ctx, p.pacman, p.tick_no || 0)
}

function drawPacman(ctx, pac, tickNo) {
  if (!pac) return
  const cx = pac.col * CELL + CELL / 2
  const cy = pac.row * CELL + CELL / 2
  const radius = CELL / 2 - 1
  const dirAngle = dirToAngle(pac.dir)
  const mouthOpen = (tickNo % 6) < 3
  const mouthSize = mouthOpen ? 0.35 : 0.05
  const start = dirAngle - Math.PI * mouthSize
  const end = dirAngle + Math.PI * mouthSize

  ctx.fillStyle = pac.alive ? "#facc15" : "#fef9c3"
  ctx.beginPath()
  ctx.moveTo(cx, cy)
  ctx.arc(cx, cy, radius, end, start + Math.PI * 2)
  ctx.closePath()
  ctx.fill()
}

function dirToAngle(dir) {
  switch (dir) {
    case "right": return 0
    case "down": return Math.PI / 2
    case "left": return Math.PI
    case "up": return -Math.PI / 2
    default: return 0
  }
}

function drawGhost(ctx, g, frightened, tickNo) {
  const cx = g.col * CELL + CELL / 2
  const cy = g.row * CELL + CELL / 2
  const radius = CELL / 2 - 1

  let color
  if (g.mode === "eaten") {
    color = "rgba(255,255,255,0.0)"  // 본체 X, 눈만.
  } else if (g.mode === "frightened") {
    // 끝나기 직전 깜빡 — frightened_ticks 작아지면 white blink (server 가 frightened bool 만 보내서
    // 정확한 ms 모름 → tick_no 패리티로 대충).
    const aboutToEnd = frightened && (tickNo % 4) < 2
    color = aboutToEnd ? "#dbeafe" : "#1e40af"
  } else {
    color = GHOST_COLORS[g.id] || "#a3a3a3"
  }

  if (g.mode !== "eaten") {
    // body — 둥근 위쪽 + 톱니 아래쪽.
    ctx.fillStyle = color
    ctx.beginPath()
    ctx.arc(cx, cy - 1, radius, Math.PI, 0, false)
    ctx.lineTo(cx + radius, cy + radius - 1)
    // 톱니 3개.
    const teeth = 3
    const teethW = (radius * 2) / teeth
    for (let i = teeth - 1; i >= 0; i--) {
      const sx = cx - radius + (i + 0.5) * teethW
      const dy = (i % 2 === 0) ? -3 : 0
      ctx.lineTo(sx, cy + radius - 1 + dy)
    }
    ctx.lineTo(cx - radius, cy + radius - 1)
    ctx.closePath()
    ctx.fill()
  }

  // eyes (frightened 시 하얀 점만).
  if (g.mode !== "frightened") {
    const eyeOff = radius * 0.4
    const dirOff = dirEyeOffset(g.dir)
    drawEye(ctx, cx - eyeOff, cy - 2, dirOff)
    drawEye(ctx, cx + eyeOff, cy - 2, dirOff)
  } else {
    // simple frightened face — 작은 두 눈.
    ctx.fillStyle = "#ffffff"
    ctx.fillRect(cx - 5, cy - 2, 2, 2)
    ctx.fillRect(cx + 3, cy - 2, 2, 2)
    // 입 — 지그재그.
    ctx.strokeStyle = "#ffffff"
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(cx - 5, cy + 4)
    ctx.lineTo(cx - 2, cy + 2)
    ctx.lineTo(cx, cy + 4)
    ctx.lineTo(cx + 2, cy + 2)
    ctx.lineTo(cx + 5, cy + 4)
    ctx.stroke()
  }
}

function dirEyeOffset(dir) {
  switch (dir) {
    case "up": return [0, -1]
    case "down": return [0, 1]
    case "left": return [-1, 0]
    case "right": return [1, 0]
    default: return [0, 0]
  }
}

function drawEye(ctx, x, y, [dx, dy]) {
  ctx.fillStyle = "#ffffff"
  ctx.beginPath()
  ctx.arc(x, y, 3, 0, Math.PI * 2)
  ctx.fill()
  ctx.fillStyle = "#1e40af"
  ctx.beginPath()
  ctx.arc(x + dx, y + dy, 1.5, 0, Math.PI * 2)
  ctx.fill()
}

export const PacmanCanvas = {
  mounted() {
    this.canvas = this.el.querySelector("canvas")
    if (!this.canvas) return
    this.ctx = this.canvas.getContext("2d")
    render(this.ctx, parsePayload(this.el))
  },

  updated() {
    if (this.ctx) render(this.ctx, parsePayload(this.el))
  },
}
