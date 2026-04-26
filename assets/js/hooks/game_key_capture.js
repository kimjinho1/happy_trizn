// 게임 키 입력 capture — 화살표 / Space 등 페이지 스크롤 회피.
//
// LiveView 의 phx-window-keydown 만 쓰면 server 가 처리해도 브라우저 기본 동작
// (화살표 → 페이지 스크롤) 이 그대로 발동. 2048, Minesweeper 같이 화살표 키
// 쓰는 페이지가 게임 키 누를 때마다 화면이 뛰어다니는 문제.
//
// 이 훅을 단 element 가 mount 되면 window keydown 을 listen + 게임 키만
// preventDefault, pushEvent("keydown", {key}) 로 server 에 전달. 다른 키 (Tab
// 등) 는 그냥 통과.
//
// data-keys 로 capture 할 키 set 명시 (csv).
//
// 예: <div phx-hook="GameKeyCapture" data-keys="ArrowUp,ArrowDown,...,w,a,s,d,...">

const DEFAULT_KEYS = [
  "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight",
  " ", "Space", "Spacebar",
  "PageUp", "PageDown", "Home", "End",
]

function isFormTarget(t) {
  if (!t || !t.tagName) return false
  const tag = t.tagName
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || Boolean(t.isContentEditable)
}

function parseKeys(el) {
  const csv = el.dataset.keys || ""
  const list = csv.split(",").map((s) => s.trim()).filter(Boolean)
  return new Set(list.length ? list : DEFAULT_KEYS)
}

export const GameKeyCapture = {
  mounted() {
    this.keys = parseKeys(this.el)
    this._keydown = (e) => this.onKeyDown(e)
    window.addEventListener("keydown", this._keydown)
  },

  updated() {
    this.keys = parseKeys(this.el)
  },

  destroyed() {
    window.removeEventListener("keydown", this._keydown)
  },

  onKeyDown(e) {
    if (isFormTarget(e.target)) return
    // 게임 capture key — preventDefault + server 로 forward.
    // Space 는 e.key === " " 인데 CSV 의 " " 가 trim 으로 사라지므로
    // "Space"/"Spacebar" alias 로 capture. server 에는 e.key 그대로 전달.
    const k = e.key
    const isSpace = k === " " && (this.keys.has("Space") || this.keys.has("Spacebar"))
    if (!this.keys.has(k) && !isSpace) return
    e.preventDefault()
    this.pushEvent("keydown", { key: k })
  },
}
