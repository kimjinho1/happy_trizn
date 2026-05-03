// Trizmon adventure 모드 — tile-based 2D canvas (Sprint 5c-3a).
// data-payload (json) — map (id/name/width/height/tiles/spawn) + player (x, y, dir).
//
// tile types:
//   grass / path / tall_grass / sand / door / wall / npc / water
// spec: docs/TRIZMON_SPEC.md §9

const CELL = 32

const TILE_COLORS = {
  grass: "#3f6d3f",
  path: "#a47c5d",
  tall_grass: "#5fa05f",
  sand: "#d8c08e",
  door: "#3b82f6",
  wall: "#404040",
  npc: "#fbbf24",
  water: "#1e40af",
}

const TILE_BORDER = {
  tall_grass: "#7fcf7f",
  door: "#60a5fa",
  npc: "#f59e0b",
}

function parsePayload(el) {
  try {
    return JSON.parse(el.dataset.payload || "{}")
  } catch (_) {
    return null
  }
}

function render(ctx, p) {
  if (!p || !p.map) return

  const map = p.map
  const player = p.player || { x: 0, y: 0, dir: "down" }

  const w = ctx.canvas.width
  const h = ctx.canvas.height

  ctx.fillStyle = "#1f1f1f"
  ctx.fillRect(0, 0, w, h)

  // tiles
  for (let y = 0; y < map.height; y++) {
    for (let x = 0; x < map.width; x++) {
      const tile = (map.tiles[y] && map.tiles[y][x]) || "wall"
      ctx.fillStyle = TILE_COLORS[tile] || "#000000"
      ctx.fillRect(x * CELL, y * CELL, CELL, CELL)

      const border = TILE_BORDER[tile]
      if (border) {
        ctx.strokeStyle = border
        ctx.lineWidth = 1
        ctx.strokeRect(x * CELL + 1, y * CELL + 1, CELL - 2, CELL - 2)
      }

      // NPC 마크
      if (tile === "npc") {
        ctx.fillStyle = "#000"
        ctx.font = "bold 18px sans-serif"
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillText("NPC", x * CELL + CELL / 2, y * CELL + CELL / 2)
      }
      // 문 표시
      if (tile === "door") {
        ctx.fillStyle = "#fff"
        ctx.font = "bold 14px sans-serif"
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillText("문", x * CELL + CELL / 2, y * CELL + CELL / 2)
      }
    }
  }

  // grid lines
  ctx.strokeStyle = "rgba(0,0,0,0.15)"
  ctx.lineWidth = 1
  for (let x = 0; x <= map.width; x++) {
    ctx.beginPath()
    ctx.moveTo(x * CELL, 0)
    ctx.lineTo(x * CELL, map.height * CELL)
    ctx.stroke()
  }
  for (let y = 0; y <= map.height; y++) {
    ctx.beginPath()
    ctx.moveTo(0, y * CELL)
    ctx.lineTo(map.width * CELL, y * CELL)
    ctx.stroke()
  }

  // player — red square + dir arrow
  const px = player.x * CELL
  const py = player.y * CELL
  ctx.fillStyle = "#ef4444"
  ctx.fillRect(px + 4, py + 4, CELL - 8, CELL - 8)

  // dir arrow (작은 흰 삼각형)
  ctx.fillStyle = "#fff"
  ctx.beginPath()
  const cx = px + CELL / 2
  const cy = py + CELL / 2
  const arrowSize = 6

  switch (player.dir) {
    case "up":
      ctx.moveTo(cx, cy - arrowSize)
      ctx.lineTo(cx - arrowSize, cy + arrowSize)
      ctx.lineTo(cx + arrowSize, cy + arrowSize)
      break
    case "down":
      ctx.moveTo(cx, cy + arrowSize)
      ctx.lineTo(cx - arrowSize, cy - arrowSize)
      ctx.lineTo(cx + arrowSize, cy - arrowSize)
      break
    case "left":
      ctx.moveTo(cx - arrowSize, cy)
      ctx.lineTo(cx + arrowSize, cy - arrowSize)
      ctx.lineTo(cx + arrowSize, cy + arrowSize)
      break
    case "right":
    default:
      ctx.moveTo(cx + arrowSize, cy)
      ctx.lineTo(cx - arrowSize, cy - arrowSize)
      ctx.lineTo(cx - arrowSize, cy + arrowSize)
      break
  }
  ctx.closePath()
  ctx.fill()
}

export const TrizmonAdventureCanvas = {
  mounted() {
    const canvas = this.el.querySelector("canvas")
    if (!canvas) return

    this.canvas = canvas
    this.ctx = canvas.getContext("2d")

    const payload = parsePayload(this.el)
    if (payload && payload.map) {
      canvas.width = payload.map.width * CELL
      canvas.height = payload.map.height * CELL
    }

    render(this.ctx, payload)
  },

  updated() {
    const payload = parsePayload(this.el)
    if (payload && payload.map && this.canvas) {
      const w = payload.map.width * CELL
      const h = payload.map.height * CELL
      if (this.canvas.width !== w) this.canvas.width = w
      if (this.canvas.height !== h) this.canvas.height = h
    }
    render(this.ctx, payload)
  },
}
