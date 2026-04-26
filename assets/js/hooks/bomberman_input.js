// Bomberman 키 입력 훅 — DAS/ARR 없이 단순 keydown.
//
// 이동 키 hold 시 OS auto-repeat 사용 (브라우저 기본 100~150ms 간격).
// 게임 키 매핑은 user_game_settings.bindings (data-key-bindings).

const ACTION_TO_SERVER = Object.freeze({
  move_up: { action: "move", dir: "up" },
  move_down: { action: "move", dir: "down" },
  move_left: { action: "move", dir: "left" },
  move_right: { action: "move", dir: "right" },
  place_bomb: { action: "place_bomb" },
  kick: { action: "kick" },
  punch: { action: "punch" },
})

const SPECIAL_ALIASES = { Space: " ", space: " ", SPACE: " " }

function normalizeKey(k) {
  if (k == null) return ""
  if (Object.prototype.hasOwnProperty.call(SPECIAL_ALIASES, k)) return SPECIAL_ALIASES[k]
  if (k.length === 1 && k !== " ") return k.toLowerCase()
  return k
}

function effectiveKey(e) {
  const code = e.code || ""
  if (/^Key[A-Z]$/.test(code)) return code.charAt(3).toLowerCase()
  if (code === "Space") return " "
  return normalizeKey(e.key)
}

function isFormTarget(t) {
  if (!t || !t.tagName) return false
  const tag = t.tagName
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || Boolean(t.isContentEditable)
}

export const BombermanInput = {
  mounted() {
    this.parseDataset()
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
      return
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
    if (!action) return
    const payload = ACTION_TO_SERVER[action]
    if (!payload) return
    e.preventDefault()
    this.pushEvent("bomberman_input", payload)
  },
}
