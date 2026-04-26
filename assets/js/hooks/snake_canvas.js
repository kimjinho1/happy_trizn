// Snake.io 캔버스 — 본인 head 중심 viewport + 매 frame 보간 + 둥근 segment.
// data-grid-size = 월드 격자 크기 (200), data-snakes / data-food (json), data-me-id, data-tick-ms.

const VIEWPORT_CELLS = 32 // viewport 안 셀 수 (32×32) — 사이드바 (리더보드+조작+채팅) 높이 매칭.
const CELL_PX = 20        // 셀 한 변 픽셀 (= 32×20 = 640px 정사각형 canvas).
const HEAD_RADIUS = CELL_PX * 0.55
const BODY_RADIUS = CELL_PX * 0.45
const FOOD_RADIUS = CELL_PX * 0.32

function parsePayload(el) {
  let snakes = []
  let food = []
  let gridSize = 200
  let tickMs = 80
  try { snakes = JSON.parse(el.dataset.snakes || "[]") } catch (_) {}
  try { food = JSON.parse(el.dataset.food || "[]") } catch (_) {}
  try { gridSize = parseInt(el.dataset.gridSize || "200", 10) || 200 } catch (_) {}
  try { tickMs = parseInt(el.dataset.tickMs || "80", 10) || 80 } catch (_) {}
  return { snakes, food, gridSize, tickMs, meId: el.dataset.meId }
}

// segment[i] 의 prev (이전 tick) 위치를 매칭. id 별로 prev 보존.
// body 가 N → N+1 (성장) — prev 의 head 기준으로 새 segment 시작 위치 fallback.
// body 가 N → N-1 (탈락 / 식사 안 함) — prev 의 tail 은 무시.
function lerpBody(prevBody, currBody, t) {
  if (!prevBody || prevBody.length === 0) return currBody.map(([r, c]) => [r, c])
  const out = []
  for (let i = 0; i < currBody.length; i++) {
    const [cr, cc] = currBody[i]
    // prev 의 같은 index — 없으면 prev 의 head (0번) — 그것도 없으면 curr 그대로.
    const prev = prevBody[i] || prevBody[0] || [cr, cc]
    const [pr, pc] = prev
    out.push([pr + (cr - pr) * t, pc + (cc - pc) * t])
  }
  return out
}

function findMyHead(snakes, meId) {
  const me = snakes.find((s) => s.is_me || s.id === meId)
  if (me && me.body && me.body.length > 0) return me.body[0]
  return null
}

function clamp(v, lo, hi) { return v < lo ? lo : v > hi ? hi : v }

function computeCamera(headRC, gridSize) {
  const half = VIEWPORT_CELLS / 2
  const [hr, hc] = headRC
  // float 카메라 (셀 단위) — 본인 head 가 항상 viewport 정중앙.
  const top = clamp(hr - half + 0.5, 0, gridSize - VIEWPORT_CELLS)
  const left = clamp(hc - half + 0.5, 0, gridSize - VIEWPORT_CELLS)
  return { top, left }
}

// 월드 셀 좌표 → 캔버스 픽셀 좌표 (float OK — anti-alias 부드럽게).
function toCanvas(r, c, cam) {
  return {
    x: (c - cam.left) * CELL_PX,
    y: (r - cam.top) * CELL_PX,
  }
}

function lighten(hex, amount) {
  if (!hex || hex[0] !== "#" || hex.length !== 7) return hex
  const r = Math.min(255, parseInt(hex.slice(1, 3), 16) + amount)
  const g = Math.min(255, parseInt(hex.slice(3, 5), 16) + amount)
  const b = Math.min(255, parseInt(hex.slice(5, 7), 16) + amount)
  return "#" + [r, g, b].map((v) => v.toString(16).padStart(2, "0")).join("")
}

function darken(hex, amount) { return lighten(hex, -amount) }

// 두 점 사이를 capsule (선분 + radius) 로 그림 — segment 자연스럽게 연결.
function drawCapsule(ctx, ax, ay, bx, by, radius) {
  ctx.beginPath()
  ctx.arc(ax, ay, radius, 0, Math.PI * 2)
  ctx.fill()
  ctx.beginPath()
  ctx.arc(bx, by, radius, 0, Math.PI * 2)
  ctx.fill()
  // 두 원 사이 직사각형 — 두께는 radius × 2.
  const dx = bx - ax
  const dy = by - ay
  const len = Math.hypot(dx, dy) || 1
  const nx = -dy / len
  const ny = dx / len
  ctx.beginPath()
  ctx.moveTo(ax + nx * radius, ay + ny * radius)
  ctx.lineTo(bx + nx * radius, by + ny * radius)
  ctx.lineTo(bx - nx * radius, by - ny * radius)
  ctx.lineTo(ax - nx * radius, ay - ny * radius)
  ctx.closePath()
  ctx.fill()
}

function render(ctx, payload, prevById, t) {
  const { snakes, food, gridSize, meId } = payload
  const w = ctx.canvas.width
  const h = ctx.canvas.height

  // 본인 head 위치 (보간된 값) — 카메라 중심.
  const me = snakes.find((s) => s.is_me || s.id === meId)
  let camHead
  if (me && me.body && me.body.length > 0) {
    const prevMe = prevById[me.id]
    const lerped = prevMe
      ? lerpBody(prevMe.body, me.body, t)
      : me.body.map(([r, c]) => [r, c + 0])
    camHead = lerped[0]
  } else {
    camHead = [gridSize / 2, gridSize / 2]
  }
  const cam = computeCamera(camHead, gridSize)

  // 배경.
  ctx.fillStyle = "#0f172a"
  ctx.fillRect(0, 0, w, h)

  // 월드 가장자리 dark zone (viewport 안에 들어오면).
  ctx.fillStyle = "#020617"
  for (let vr = 0; vr < VIEWPORT_CELLS; vr++) {
    for (let vc = 0; vc < VIEWPORT_CELLS; vc++) {
      const r = Math.floor(cam.top) + vr
      const c = Math.floor(cam.left) + vc
      if (r < 0 || r >= gridSize || c < 0 || c >= gridSize) {
        ctx.fillRect(vc * CELL_PX, vr * CELL_PX, CELL_PX, CELL_PX)
      }
    }
  }

  // 옅은 격자 선 (월드 좌표 10 배수).
  ctx.strokeStyle = "rgba(148, 163, 184, 0.08)"
  ctx.lineWidth = 1
  const startR = Math.ceil(cam.top / 10) * 10
  for (let r = startR; r <= cam.top + VIEWPORT_CELLS + 1; r += 10) {
    const y = (r - cam.top) * CELL_PX + 0.5
    ctx.beginPath()
    ctx.moveTo(0, y)
    ctx.lineTo(w, y)
    ctx.stroke()
  }
  const startC = Math.ceil(cam.left / 10) * 10
  for (let c = startC; c <= cam.left + VIEWPORT_CELLS + 1; c += 10) {
    const x = (c - cam.left) * CELL_PX + 0.5
    ctx.beginPath()
    ctx.moveTo(x, 0)
    ctx.lineTo(x, h)
    ctx.stroke()
  }

  // food — 둥근 점.
  ctx.fillStyle = "#fde047"
  for (const [r, c] of food) {
    const cx = (c + 0.5 - cam.left) * CELL_PX
    const cy = (r + 0.5 - cam.top) * CELL_PX
    if (cx < -CELL_PX || cy < -CELL_PX || cx > w + CELL_PX || cy > h + CELL_PX) continue
    ctx.beginPath()
    ctx.arc(cx, cy, FOOD_RADIUS, 0, Math.PI * 2)
    ctx.fill()
  }

  // snakes — 보간된 body 를 capsule chain 으로 그림.
  for (const s of snakes) {
    if (!s.body || s.body.length === 0) continue

    const prev = prevById[s.id]
    const body = prev ? lerpBody(prev.body, s.body, t) : s.body.map(([r, c]) => [r, c])

    const alpha = s.alive ? 1 : 0.25
    ctx.globalAlpha = alpha

    const baseColor = s.color || "#22c55e"
    const headColor = lighten(baseColor, 30)
    const outline = darken(baseColor, 60)

    // outline (살짝 굵게 어두운 색).
    ctx.fillStyle = outline
    for (let i = 0; i < body.length - 1; i++) {
      const [r1, c1] = body[i]
      const [r2, c2] = body[i + 1]
      const a = toCanvas(r1, c1, cam)
      const b = toCanvas(r2, c2, cam)
      drawCapsule(
        ctx,
        a.x + CELL_PX / 2,
        a.y + CELL_PX / 2,
        b.x + CELL_PX / 2,
        b.y + CELL_PX / 2,
        BODY_RADIUS + 1.5,
      )
    }

    // body (메인 색).
    ctx.fillStyle = baseColor
    for (let i = 1; i < body.length - 1; i++) {
      const [r1, c1] = body[i]
      const [r2, c2] = body[i + 1]
      const a = toCanvas(r1, c1, cam)
      const b = toCanvas(r2, c2, cam)
      drawCapsule(
        ctx,
        a.x + CELL_PX / 2,
        a.y + CELL_PX / 2,
        b.x + CELL_PX / 2,
        b.y + CELL_PX / 2,
        BODY_RADIUS,
      )
    }

    // head.
    if (body.length > 0) {
      const [hr, hc] = body[0]
      const hp = toCanvas(hr, hc, cam)
      const hx = hp.x + CELL_PX / 2
      const hy = hp.y + CELL_PX / 2

      // head→neck capsule (head 가 두꺼움).
      if (body.length >= 2) {
        const [nr, nc] = body[1]
        const np = toCanvas(nr, nc, cam)
        ctx.fillStyle = headColor
        drawCapsule(ctx, hx, hy, np.x + CELL_PX / 2, np.y + CELL_PX / 2, HEAD_RADIUS)
      } else {
        ctx.fillStyle = headColor
        ctx.beginPath()
        ctx.arc(hx, hy, HEAD_RADIUS, 0, Math.PI * 2)
        ctx.fill()
      }

      // 본인 ring.
      if (s.is_me || s.id === meId) {
        ctx.strokeStyle = "#ffffff"
        ctx.lineWidth = 2
        ctx.beginPath()
        ctx.arc(hx, hy, HEAD_RADIUS - 1, 0, Math.PI * 2)
        ctx.stroke()
      }

      // 눈 (head 뱀같은 느낌) — 진행 방향 기준 좌우 두 점.
      if (s.alive && body.length >= 2) {
        const [nr, nc] = body[1]
        const dx = hc - nc
        const dy = hr - nr
        const len = Math.hypot(dx, dy) || 1
        const fx = dx / len
        const fy = dy / len
        // 좌우 perpendicular.
        const pxv = -fy
        const pyv = fx
        const eyeOffset = HEAD_RADIUS * 0.5
        const eyeRadius = Math.max(2, HEAD_RADIUS * 0.22)
        const ex1 = hx + fx * (HEAD_RADIUS * 0.2) + pxv * eyeOffset
        const ey1 = hy + fy * (HEAD_RADIUS * 0.2) + pyv * eyeOffset
        const ex2 = hx + fx * (HEAD_RADIUS * 0.2) - pxv * eyeOffset
        const ey2 = hy + fy * (HEAD_RADIUS * 0.2) - pyv * eyeOffset
        ctx.fillStyle = "#ffffff"
        ctx.beginPath()
        ctx.arc(ex1, ey1, eyeRadius, 0, Math.PI * 2)
        ctx.arc(ex2, ey2, eyeRadius, 0, Math.PI * 2)
        ctx.fill()
        ctx.fillStyle = "#0f172a"
        ctx.beginPath()
        ctx.arc(ex1 + fx * 1.2, ey1 + fy * 1.2, Math.max(1, eyeRadius * 0.55), 0, Math.PI * 2)
        ctx.arc(ex2 + fx * 1.2, ey2 + fy * 1.2, Math.max(1, eyeRadius * 0.55), 0, Math.PI * 2)
        ctx.fill()
      }
    }
    ctx.globalAlpha = 1
  }

  // HUD — 좌상단 좌표 (head 셀 기준 round).
  ctx.fillStyle = "rgba(255, 255, 255, 0.5)"
  ctx.font = "11px monospace"
  const hr = Math.round(camHead[0])
  const hc = Math.round(camHead[1])
  ctx.fillText(`(${hr}, ${hc}) / ${gridSize}`, 6, h - 6)
}

export const SnakeCanvas = {
  mounted() {
    this.canvas = this.el.querySelector("canvas")
    if (!this.canvas) return
    this.canvas.width = VIEWPORT_CELLS * CELL_PX
    this.canvas.height = VIEWPORT_CELLS * CELL_PX
    this.ctx = this.canvas.getContext("2d")
    this.prevById = {}
    this.lastTickAt = performance.now()
    this.payload = parsePayload(this.el)

    const tick = () => {
      const now = performance.now()
      const t = Math.min(1, (now - this.lastTickAt) / (this.payload.tickMs || 80))
      render(this.ctx, this.payload, this.prevById, t)
      this._raf = requestAnimationFrame(tick)
    }
    this._raf = requestAnimationFrame(tick)
  },

  updated() {
    if (!this.canvas) return
    // server tick 도착 — 이전 payload 의 snake 들을 prev 로 저장.
    const prev = {}
    for (const s of this.payload.snakes || []) prev[s.id] = s
    this.prevById = prev
    this.payload = parsePayload(this.el)
    this.lastTickAt = performance.now()
  },

  destroyed() {
    if (this._raf) cancelAnimationFrame(this._raf)
  },
}
