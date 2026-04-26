// Snake.io 키 입력 훅 — 4 방향만, set_dir 이벤트.
// 키 매핑은 user_game_settings.bindings (data-key-bindings).
// 기본: ArrowUp/Down/Left/Right + WASD.

const ACTION_TO_DIR = Object.freeze({
  move_up: "up",
  move_down: "down",
  move_left: "left",
  move_right: "right",
})

function normalizeKey(k) {
  if (k == null) return ""
  if (k.length === 1 && k !== " ") return k.toLowerCase()
  return k
}

function effectiveKey(e) {
  const code = e.code || ""
  if (/^Key[A-Z]$/.test(code)) return code.charAt(3).toLowerCase()
  return normalizeKey(e.key)
}

function isFormTarget(t) {
  if (!t || !t.tagName) return false
  const tag = t.tagName
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || Boolean(t.isContentEditable)
}

export const SnakeInput = {
  mounted() {
    this.parseDataset()
    // 같은 dir 연타 throttle — 25ms 간격 이내 중복 무시.
    this.lastSent = { dir: null, ts: 0 }
    this._keydown = (e) => this.onKeyDown(e)
    window.addEventListener("keydown", this._keydown)
  },

  updated() {
    this.parseDataset()
  },

  destroyed() {
    window.removeEventListener("keydown", this._keydown)
  },

  parseDataset() {
    this.keyToAction = {}
    let bindings = {}
    try {
      bindings = JSON.parse(this.el.dataset.keyBindings || "{}")
    } catch (_e) {
      // 기본 fallback.
      bindings = {
        move_up: ["ArrowUp", "w"],
        move_down: ["ArrowDown", "s"],
        move_left: ["ArrowLeft", "a"],
        move_right: ["ArrowRight", "d"],
      }
    }
    // 빈 bindings 도 fallback.
    if (!bindings || Object.keys(bindings).length === 0) {
      bindings = {
        move_up: ["ArrowUp", "w"],
        move_down: ["ArrowDown", "s"],
        move_left: ["ArrowLeft", "a"],
        move_right: ["ArrowRight", "d"],
      }
    }
    for (const [action, keys] of Object.entries(bindings)) {
      if (!Array.isArray(keys)) continue
      for (const k of keys) {
        const norm = normalizeKey(k)
        if (norm) this.keyToAction[norm] = action
      }
    }
  },

  onKeyDown(e) {
    if (isFormTarget(e.target)) return
    const action = this.keyToAction[effectiveKey(e)]
    const dir = ACTION_TO_DIR[action]
    if (!dir) return
    e.preventDefault()
    const now = Date.now()
    if (this.lastSent.dir === dir && now - this.lastSent.ts < 25) return
    this.lastSent = { dir, ts: now }
    this.pushEvent("snake_set_dir", { dir })
  },
}
