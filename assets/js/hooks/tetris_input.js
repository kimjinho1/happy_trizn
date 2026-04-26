// Tetris 키 입력 훅 — 서버 사이드 LiveView 와 클라이언트 사이드 DAS/ARR 분리.
//
// 책임:
//   1. data-key-bindings JSON 읽고 (server 가 user_game_settings 로 주입)
//      keyboard event → game action 매핑 테이블 빌드.
//   2. keydown 시 즉시 1회 fire. repeatable action 은 DAS 후 ARR 로 자동 반복.
//   3. keyup / blur 시 timer 정리.
//   4. 옵션 모달 등 input 필드에서는 비활성 (form target skip).
//
// 디자인 원칙:
//   - 키 매칭은 e.code 기반 (layout / IME 독립). e.key 는 fallback.
//   - 단일 문자 binding 은 case-insensitive (대소문자 무관).
//   - 모든 게임별 action / 키 정규화는 한 군데 (이 파일) 에서.
//   - 서버 action 이름 (Tetris GenServer 가 받는 string) 은 ACTION_TO_SERVER 에서 매핑.

// ============================================================================
// Constants — 새 action 추가 시 여기만 손봄.
// ============================================================================

// DAS+ARR 자동 반복 적용할 action.
const REPEATABLE_ACTIONS = new Set(["move_left", "move_right", "soft_drop"])

// 클라이언트 action 이름 → Tetris GenServer 의 input action string.
const ACTION_TO_SERVER = Object.freeze({
  move_left: "left",
  move_right: "right",
  soft_drop: "soft_drop",
  hard_drop: "hard_drop",
  rotate_cw: "rotate_cw",
  rotate_ccw: "rotate_ccw",
  rotate_180: "rotate_180",
  hold: "hold",
})

// 친화 표기 → KeyboardEvent.key 형식.
const SPECIAL_KEY_ALIASES = Object.freeze({
  Space: " ",
  space: " ",
  SPACE: " ",
  Tab: "\t",
})

// ============================================================================
// Helpers
// ============================================================================

// 친화 이름 + 문자/숫자 case-insensitive 정규화.
// 단일 문자만 lowercase. ArrowLeft / Shift / Control 등은 그대로.
function normalizeKey(k) {
  if (k == null) return ""
  if (Object.prototype.hasOwnProperty.call(SPECIAL_KEY_ALIASES, k)) {
    return SPECIAL_KEY_ALIASES[k]
  }
  if (k.length === 1 && k !== " ") return k.toLowerCase()
  return k
}

// KeyboardEvent → 매칭에 쓸 effective key.
//
// e.code 우선 (layout / IME 독립).
//   - "KeyA" ~ "KeyZ" → "a" ~ "z"
//   - "Digit0" ~ "Digit9" → "0" ~ "9"
//   - "Space" → " "
//   - "Tab" → "\t"
//   - 그 외 → e.key 정규화 (Arrow*, Shift, Control, Escape ...)
function effectiveKey(e) {
  const code = e.code || ""

  if (/^Key[A-Z]$/.test(code)) return code.charAt(3).toLowerCase()
  if (/^Digit[0-9]$/.test(code)) return code.charAt(5)
  if (code === "Space") return " "
  if (code === "Tab") return "\t"

  return normalizeKey(e.key)
}

// 입력 필드 안 keystroke 무시 (옵션 모달 등의 input/textarea).
function isFormTarget(t) {
  if (!t || !t.tagName) return false
  const tag = t.tagName
  if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return true
  return Boolean(t.isContentEditable)
}

// ============================================================================
// Hook
// ============================================================================

export const TetrisInput = {
  mounted() {
    this.activeTimers = new Map() // action → { dasTimer, arrTimer, keys: Set }
    this.heldKeys = new Set()
    this.parseDataset()

    this._keydown = (e) => this.onKeyDown(e)
    this._keyup = (e) => this.onKeyUp(e)
    this._blur = () => this.releaseAll()

    window.addEventListener("keydown", this._keydown)
    window.addEventListener("keyup", this._keyup)
    window.addEventListener("blur", this._blur)
  },

  updated() {
    // 서버가 data-* 갱신 시 (옵션 저장 후) 재파싱.
    this.parseDataset()
  },

  destroyed() {
    window.removeEventListener("keydown", this._keydown)
    window.removeEventListener("keyup", this._keyup)
    window.removeEventListener("blur", this._blur)
    this.releaseAll()
  },

  // ----------------------------------------------------------------------
  // Dataset → 키 매핑 테이블
  // ----------------------------------------------------------------------

  parseDataset() {
    this.das = parseInt(this.el.dataset.das || "133", 10)
    this.arr = parseInt(this.el.dataset.arr || "10", 10)
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

  // ----------------------------------------------------------------------
  // Event handlers
  // ----------------------------------------------------------------------

  onKeyDown(e) {
    if (isFormTarget(e.target)) return

    const action = this.keyToAction[effectiveKey(e)]
    if (!action) return

    e.preventDefault()
    const keyId = e.code || e.key
    if (this.heldKeys.has(keyId)) return // OS 자동 반복 무시 — 우리 DAS/ARR 만 사용
    this.heldKeys.add(keyId)

    this.fire(action)

    if (REPEATABLE_ACTIONS.has(action)) this.startAutoRepeat(action, keyId)
  },

  onKeyUp(e) {
    if (isFormTarget(e.target)) return
    const action = this.keyToAction[effectiveKey(e)]
    if (!action) return

    const keyId = e.code || e.key
    this.heldKeys.delete(keyId)

    const slot = this.activeTimers.get(action)
    if (!slot) return
    slot.keys.delete(keyId)

    if (slot.keys.size === 0) this.stopAutoRepeat(action)
  },

  // ----------------------------------------------------------------------
  // DAS / ARR
  // ----------------------------------------------------------------------

  startAutoRepeat(action, keyId) {
    const existing = this.activeTimers.get(action)
    if (existing) {
      // 같은 action 의 다른 키 (e.g. ArrowLeft + j) 추가만, 새 timer 안 만듦.
      existing.keys.add(keyId)
      return
    }

    const dasTimer = setTimeout(() => {
      const arrInterval = Math.max(this.arr, 1)
      this.fire(action)
      const arrTimer = setInterval(() => this.fire(action), arrInterval)
      const slot = this.activeTimers.get(action)
      if (slot) {
        slot.arrTimer = arrTimer
        slot.dasTimer = null
      }
    }, this.das)

    this.activeTimers.set(action, {
      dasTimer,
      arrTimer: null,
      keys: new Set([keyId]),
    })
  },

  stopAutoRepeat(action) {
    const slot = this.activeTimers.get(action)
    if (!slot) return
    if (slot.dasTimer) clearTimeout(slot.dasTimer)
    if (slot.arrTimer) clearInterval(slot.arrTimer)
    this.activeTimers.delete(action)
  },

  releaseAll() {
    for (const action of [...this.activeTimers.keys()]) this.stopAutoRepeat(action)
    this.heldKeys.clear()
  },

  // ----------------------------------------------------------------------
  // Server push
  // ----------------------------------------------------------------------

  fire(action) {
    const serverAction = ACTION_TO_SERVER[action]
    if (!serverAction) return
    this.pushEvent("input", { action: serverAction })
  },
}
