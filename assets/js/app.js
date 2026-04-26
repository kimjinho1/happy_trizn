// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/happy_trizn"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// LiveView Hooks
const Hooks = {
  // 채팅 메시지 컨테이너 — flex-col-reverse 라 새 메시지 추가 시 자동으로 위에 쌓임.
  // 사용자가 스크롤로 위쪽을 보고 있으면 자동 스크롤 안 함 (mid-scroll 보존).
  ChatScroll: {
    mounted() {
      this.handleEvent("chat_message_added", () => this.scrollToBottom())
    },
    updated() {
      // flex-col-reverse 환경에서 scrollTop=0 이 가장 최신.
      if (this.el.scrollTop > -50) {
        this.el.scrollTop = 0
      }
    },
    scrollToBottom() {
      this.el.scrollTop = 0
    }
  },

  // 채팅 입력 form — server 가 "chat:reset_input" event 보내면 input value 비움.
  // morphdom 은 typed input 의 value property 안 건드림. server-driven 명시 reset.
  ChatReset: {
    mounted() {
      this.handleEvent("chat:reset_input", () => {
        const input = this.el.querySelector('input[name="message"]')
        if (input) {
          input.value = ""
          input.focus()
        }
      })
    },
  },

  // Tetris 입력 — 키 hold 시 DAS (Delayed Auto Shift) 후 ARR (Auto Repeat Rate) 로
  // 자동 반복. 서버에 phx-event "key" 또는 "input" push.
  //
  // - left/right/soft_drop = 반복 가능 (DAS+ARR).
  // - rotate_*/hard_drop/hold = 1회 발동 (반복 없음).
  // - data-das, data-arr (ms) — el 에서 읽음.
  // - data-key-bindings JSON — { "move_left": ["ArrowLeft", "j"], ... }.
  //
  // 같은 키 두 개 (e.g. ArrowLeft + j) 가 동시에 눌리면 OR — 둘 다 release 후 멈춤.
  TetrisInput: {
    mounted() {
      this.repeatable = new Set(["move_left", "move_right", "soft_drop"])
      this.actionToServer = {
        "move_left": "left",
        "move_right": "right",
        "soft_drop": "soft_drop",
        "hard_drop": "hard_drop",
        "rotate_cw": "rotate_cw",
        "rotate_ccw": "rotate_ccw",
        "rotate_180": "rotate_180",
        "hold": "hold",
      }

      this.parseDataset()
      this.activeTimers = new Map()  // action → {dasTimer, arrTimer}
      this.heldKeys = new Set()

      this._keydown = (e) => this.onKeyDown(e)
      this._keyup = (e) => this.onKeyUp(e)
      this._blur = () => this.releaseAll()

      window.addEventListener("keydown", this._keydown)
      window.addEventListener("keyup", this._keyup)
      window.addEventListener("blur", this._blur)
    },
    updated() {
      // server 가 data attr 갱신 시 (e.g. 옵션 저장 후) 다시 파싱.
      this.parseDataset()
    },
    destroyed() {
      window.removeEventListener("keydown", this._keydown)
      window.removeEventListener("keyup", this._keyup)
      window.removeEventListener("blur", this._blur)
      this.releaseAll()
    },
    parseDataset() {
      this.das = parseInt(this.el.dataset.das || "133", 10)
      this.arr = parseInt(this.el.dataset.arr || "10", 10)
      try {
        const bindings = JSON.parse(this.el.dataset.keyBindings || "{}")
        // key → action lookup map (한 키는 마지막 매칭 action 으로).
        // normalize: "Space"/"space" → " ", "Tab" → "\t", 그 외 lower → 원본 + lower 둘 다 등록.
        this.keyToAction = {}
        for (const [action, keys] of Object.entries(bindings)) {
          if (!Array.isArray(keys)) continue
          for (const k of keys) {
            const norm = this.normalizeKey(k)
            this.keyToAction[norm] = action
          }
        }
      } catch (_e) {
        this.keyToAction = {}
      }
    },
    normalizeKey(k) {
      if (k === "Space" || k === "space" || k === "SPACE") return " "
      if (k === "Tab") return "\t"
      return k
    },
    onKeyDown(e) {
      const action = this.keyToAction[e.key]
      if (!action) return
      e.preventDefault()
      const keyId = e.key
      if (this.heldKeys.has(keyId)) return  // OS auto-repeat 무시 (manual ARR 만 사용)
      this.heldKeys.add(keyId)

      this.fire(action)

      if (this.repeatable.has(action)) {
        // 이미 동일 action 의 타이머 있으면 스킵 (다른 키로 같은 action — OR)
        if (this.activeTimers.has(action)) return

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

        this.activeTimers.set(action, { dasTimer, arrTimer: null, keys: new Set([keyId]) })
      }
    },
    onKeyUp(e) {
      const action = this.keyToAction[e.key]
      if (!action) return
      const keyId = e.key
      this.heldKeys.delete(keyId)

      const slot = this.activeTimers.get(action)
      if (!slot) return
      slot.keys.delete(keyId)

      // 같은 action 에 매핑된 다른 키가 아직 눌려있으면 유지.
      if (slot.keys.size === 0) {
        if (slot.dasTimer) clearTimeout(slot.dasTimer)
        if (slot.arrTimer) clearInterval(slot.arrTimer)
        this.activeTimers.delete(action)
      }
    },
    releaseAll() {
      for (const slot of this.activeTimers.values()) {
        if (slot.dasTimer) clearTimeout(slot.dasTimer)
        if (slot.arrTimer) clearInterval(slot.arrTimer)
      }
      this.activeTimers.clear()
      this.heldKeys.clear()
    },
    fire(action) {
      const serverAction = this.actionToServer[action]
      if (!serverAction) return
      this.pushEvent("input", { action: serverAction })
    },
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

