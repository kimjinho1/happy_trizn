// TetrisCanvas — Sprint 3j. HTML5 Canvas Tetris board renderer.
//
// 사용:
//   <canvas
//     id="tetris-canvas-me"
//     phx-hook="TetrisCanvas"
//     data-board={Jason.encode!(visible_board)}
//     data-skin={skin}
//     data-grid={grid_style}
//     data-cell-size="28"
//     data-pending="0"
//   ></canvas>
//
// data-board: 22-row 또는 20-row board JSON. 각 row 는 10 cell.
// cell 형식: nil → null, atom → string ("i"/"o"/.../"garbage"), {ghost, type} → "g_t".
//
// 매 LiveView updated() 시 redraw. mounted() 시 canvas size 결정.

// Skin → piece type → CSS color. Tailwind palette 와 일치.
const SKINS = {
  default_jstris: {
    i: "#22d3ee", // cyan-400
    o: "#facc15", // yellow-400
    t: "#a855f7", // purple-500
    s: "#22c55e", // green-500
    z: "#ef4444", // red-500
    l: "#f97316", // orange-500
    j: "#3b82f6", // blue-500
    garbage: "#6b7280", // gray-500
  },
  vivid: {
    i: "#0891b2", // cyan-600
    o: "#eab308", // yellow-500
    t: "#7e22ce", // purple-700
    s: "#15803d", // green-700
    z: "#b91c1c", // red-700
    l: "#ea580c", // orange-600
    j: "#1d4ed8", // blue-700
    garbage: "#6b7280",
  },
  monochrome: {
    i: "#cbd5e1", // slate-300
    o: "#e2e8f0", // slate-200
    t: "#64748b", // slate-500
    s: "#94a3b8", // slate-400
    z: "#475569", // slate-600
    l: "#cbd5e1",
    j: "#334155", // slate-700
    garbage: "#6b7280",
  },
  neon: {
    i: "#67e8f9", // cyan-300
    o: "#fde047", // yellow-300
    t: "#e879f9", // fuchsia-400
    s: "#a3e635", // lime-400
    z: "#fb7185", // rose-400
    l: "#fbbf24", // amber-400
    j: "#818cf8", // indigo-400
    garbage: "#6b7280",
  },
}

const GRID_LINE_RGBA = "rgba(255, 255, 255, 0.05)"
const EMPTY_BG = "#0a0a0a"

function paletteFor(skin) {
  return SKINS[skin] || SKINS.default_jstris
}

function decodeCell(c) {
  if (c === null || c === undefined) return null
  if (typeof c === "string") {
    if (c.startsWith("g_")) return { kind: "ghost", type: c.slice(2) }
    return { kind: "solid", type: c }
  }
  // 서버에서 atom 으로 인코딩 — Jason 이 atom 을 string 으로 자동 변환.
  return null
}

export const TetrisCanvas = {
  mounted() {
    this.draw()
  },
  updated() {
    this.draw()
  },
  draw() {
    const canvas = this.el
    const cellSize = parseInt(canvas.dataset.cellSize || "28", 10)
    const skin = canvas.dataset.skin || "default_jstris"
    const gridStyle = canvas.dataset.grid || "standard"

    let board
    try {
      board = JSON.parse(canvas.dataset.board || "[]")
    } catch (e) {
      console.error("TetrisCanvas: invalid data-board JSON", e)
      return
    }

    // 22-row board 일 시 hidden 2 drop, 20-row 만 표시.
    const visible = board.length === 22 ? board.slice(2) : board
    const rows = visible.length
    const cols = visible[0]?.length || 10

    canvas.width = cols * cellSize
    canvas.height = rows * cellSize

    const ctx = canvas.getContext("2d")
    ctx.fillStyle = EMPTY_BG
    ctx.fillRect(0, 0, canvas.width, canvas.height)

    const palette = paletteFor(skin)
    const showGrid = gridStyle !== "none"

    for (let r = 0; r < rows; r++) {
      const row = visible[r]
      for (let c = 0; c < cols; c++) {
        const x = c * cellSize
        const y = r * cellSize
        const cell = decodeCell(row[c])

        if (cell) {
          if (cell.kind === "ghost") {
            const color = palette[cell.type] || "#888"
            ctx.fillStyle = color + "66" // ~40% alpha hex
            ctx.fillRect(x + 1, y + 1, cellSize - 2, cellSize - 2)
            ctx.strokeStyle = color
            ctx.lineWidth = 2
            ctx.strokeRect(x + 1, y + 1, cellSize - 2, cellSize - 2)
          } else {
            ctx.fillStyle = palette[cell.type] || "#888"
            ctx.fillRect(x, y, cellSize, cellSize)
          }
        }

        if (showGrid) {
          ctx.strokeStyle = GRID_LINE_RGBA
          ctx.lineWidth = 1
          ctx.strokeRect(x + 0.5, y + 0.5, cellSize - 1, cellSize - 1)
        }
      }
    }
  },
}
