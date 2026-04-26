// Snake.io 캔버스 렌더 훅 — server payload 를 본인 head 중심 카메라로 viewport 만 그림.
// data-grid-size = 월드 격자 크기 (200), data-snakes / data-food (json), data-me-id.
// 클라이언트에서 viewport 크기 (셀 갯수) + 셀 픽셀 크기 결정.

const VIEWPORT_CELLS = 40 // viewport 안 보이는 셀 갯수 (40×40)
const CELL_PX = 16 // 셀 한 변 픽셀 (= 640 canvas 자동 매칭)

function parsePayload(el) {
  let snakes = []
  let food = []
  let gridSize = 200
  try { snakes = JSON.parse(el.dataset.snakes || "[]") } catch (_) {}
  try { food = JSON.parse(el.dataset.food || "[]") } catch (_) {}
  try { gridSize = parseInt(el.dataset.gridSize || "200", 10) || 200 } catch (_) {}
  return { snakes, food, gridSize, meId: el.dataset.meId }
}

// 본인 (alive 가 살아있는 본인 또는 마지막 사망 위치 fallback) head 좌표.
function findMyHead(snakes, meId) {
  const me = snakes.find((s) => s.is_me || s.id === meId)
  if (me && me.body && me.body.length > 0) return me.body[0]
  return null
}

// 카메라 중심 → viewport 좌상단 셀 좌표 (월드 가장자리에 도달 시 clamp).
function computeCamera(headRC, gridSize) {
  const half = Math.floor(VIEWPORT_CELLS / 2)
  const [hr, hc] = headRC
  const top = Math.max(0, Math.min(gridSize - VIEWPORT_CELLS, hr - half))
  const left = Math.max(0, Math.min(gridSize - VIEWPORT_CELLS, hc - half))
  return { top, left }
}

// 셀 (r, c) 가 viewport 안인지 + 캔버스 좌표.
function viewportCell(r, c, cam) {
  const vr = r - cam.top
  const vc = c - cam.left
  if (vr < 0 || vr >= VIEWPORT_CELLS || vc < 0 || vc >= VIEWPORT_CELLS) return null
  return { x: vc * CELL_PX, y: vr * CELL_PX }
}

function render(canvas, payload) {
  const { snakes, food, gridSize, meId } = payload
  const ctx = canvas.getContext("2d")
  const w = canvas.width
  const h = canvas.height

  // 카메라 중심: 본인 head. 없으면 (alive 없을 때) 월드 중앙.
  const head = findMyHead(snakes, meId) || [Math.floor(gridSize / 2), Math.floor(gridSize / 2)]
  const cam = computeCamera(head, gridSize)

  // 배경.
  ctx.fillStyle = "#0f172a"
  ctx.fillRect(0, 0, w, h)

  // 월드 가장자리 — viewport 안에 들어오면 외곽 표시 (검정 darker zone).
  ctx.fillStyle = "#020617"
  for (let vr = 0; vr < VIEWPORT_CELLS; vr++) {
    for (let vc = 0; vc < VIEWPORT_CELLS; vc++) {
      const r = cam.top + vr
      const c = cam.left + vc
      if (r < 0 || r >= gridSize || c < 0 || c >= gridSize) {
        ctx.fillRect(vc * CELL_PX, vr * CELL_PX, CELL_PX, CELL_PX)
      }
    }
  }

  // 격자 (10셀마다 옅은 선) — viewport 기준.
  ctx.strokeStyle = "rgba(148, 163, 184, 0.07)"
  ctx.lineWidth = 1
  // 월드 좌표 기준 10 배수 선만.
  for (let r = Math.ceil(cam.top / 10) * 10; r <= cam.top + VIEWPORT_CELLS; r += 10) {
    const y = (r - cam.top) * CELL_PX + 0.5
    ctx.beginPath()
    ctx.moveTo(0, y)
    ctx.lineTo(w, y)
    ctx.stroke()
  }
  for (let c = Math.ceil(cam.left / 10) * 10; c <= cam.left + VIEWPORT_CELLS; c += 10) {
    const x = (c - cam.left) * CELL_PX + 0.5
    ctx.beginPath()
    ctx.moveTo(x, 0)
    ctx.lineTo(x, h)
    ctx.stroke()
  }

  // food.
  ctx.fillStyle = "#fde047"
  for (const [r, c] of food) {
    const v = viewportCell(r, c, cam)
    if (v) ctx.fillRect(v.x + 1, v.y + 1, CELL_PX - 2, CELL_PX - 2)
  }

  // snake 본체.
  for (const s of snakes) {
    if (!s.body || s.body.length === 0) continue
    const alpha = s.alive ? 1 : 0.25
    ctx.globalAlpha = alpha

    // 몸통.
    ctx.fillStyle = s.color || "#22c55e"
    for (let i = 1; i < s.body.length; i++) {
      const [r, c] = s.body[i]
      const v = viewportCell(r, c, cam)
      if (v) ctx.fillRect(v.x, v.y, CELL_PX, CELL_PX)
    }

    // head 강조.
    const [hr, hc] = s.body[0]
    const vh = viewportCell(hr, hc, cam)
    if (vh) {
      ctx.fillStyle = lighten(s.color || "#22c55e", 30)
      ctx.fillRect(vh.x, vh.y, CELL_PX, CELL_PX)
      if (s.is_me || s.id === meId) {
        ctx.strokeStyle = "#ffffff"
        ctx.lineWidth = 2
        ctx.strokeRect(vh.x + 1, vh.y + 1, CELL_PX - 2, CELL_PX - 2)
      }
    }
    ctx.globalAlpha = 1
  }

  // HUD — 좌상단 좌표 표시 (디버깅용 + 위치감).
  ctx.fillStyle = "rgba(255, 255, 255, 0.5)"
  ctx.font = "11px monospace"
  ctx.fillText(`(${head[0]}, ${head[1]}) / ${gridSize}`, 6, h - 6)
}

// 간단 hex lighten — RR GG BB 각각 +amount (cap 255).
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
    if (!this.canvas) return
    // viewport 픽셀 크기 강제 — 셀 사이즈 × viewport 셀 갯수.
    this.canvas.width = VIEWPORT_CELLS * CELL_PX
    this.canvas.height = VIEWPORT_CELLS * CELL_PX
    render(this.canvas, parsePayload(this.el))
  },

  updated() {
    if (this.canvas) render(this.canvas, parsePayload(this.el))
  },
}
