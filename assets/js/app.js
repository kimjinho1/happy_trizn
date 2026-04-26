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
import {TetrisInput} from "./hooks/tetris_input"
import {TetrisSound} from "./hooks/tetris_sound"
import {TetrisCanvas} from "./hooks/tetris_canvas"
import {SkribblCanvas} from "./hooks/skribbl_canvas"
import {BombermanInput} from "./hooks/bomberman_input"
import {SnakeInput} from "./hooks/snake_input"
import {SnakeCanvas} from "./hooks/snake_canvas"
import {GameKeyCapture} from "./hooks/game_key_capture"
import {PacmanCanvas} from "./hooks/pacman_canvas"
import {MinesweeperCell} from "./hooks/minesweeper_cell"
// DM 알림 — side-effect: window phx:dm:notify listener 등록.
import "./dm_notify"

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

  // 채팅 / 입력 form — server 가 "chat:reset_input" event 보내면 모든 text input
  // value 비움. morphdom 은 typed input value 안 건드림 → 명시 reset.
  ChatReset: {
    mounted() {
      this.handleEvent("chat:reset_input", () => {
        // input[name=message] 우선, 없으면 form 안 모든 type=text input.
        const named = this.el.querySelector('input[name="message"]')
        const inputs = named ? [named] : this.el.querySelectorAll('input[type="text"], textarea')
        let focused = false
        inputs.forEach((i) => {
          i.value = ""
          if (!focused && !i.disabled) {
            i.focus()
            focused = true
          }
        })
      })
    },
  },

  // Tetris 키 입력 — 별도 모듈 (./hooks/tetris_input.js).
  TetrisInput,
  // Tetris 효과음 — WebAudio 합성 (./hooks/tetris_sound.js).
  TetrisSound,
  // Tetris HTML5 Canvas renderer — Sprint 3j (opt-in via tetris_renderer 옵션).
  TetrisCanvas,
  // Skribbl 캔버스 — drawer 그리기 + 모든 사람 보기.
  SkribblCanvas,
  // Bomberman 키 입력 — 방향키 + 폭탄 설치.
  BombermanInput,
  // Snake.io 키 입력 — 4 방향만, set_dir 이벤트.
  SnakeInput,
  // Snake.io 캔버스 렌더 — server 가 보낸 snakes/food payload.
  SnakeCanvas,
  // 게임 키 capture — 화살표 등 page scroll 막고 server 로 forward.
  GameKeyCapture,
  // Pac-Man 캔버스 렌더 — 28×31 maze + ghost AI + dot/pellet.
  PacmanCanvas,
  // 지뢰찾기 셀 — 우클릭 contextmenu → flag pushEvent.
  MinesweeperCell,

  // 게임 페이지 안 에서 top-nav ⚙️ 옵션 클릭 시 modal 열기.
  // root.html.heex 의 옵션 버튼이 'phx:open-settings' window 이벤트 dispatch →
  // 게임 LV 컨테이너에 hook 부착되어 있으면 이걸 받아서 LV로 push, 모달 open.
  // 게임 LV 가 아니면 버튼 default href 로 /settings/games 이동.
  OpenSettingsBridge: {
    mounted() {
      this._listener = (e) => {
        e?.preventDefault?.()
        this.pushEvent("open_settings", {})
      }
      window.addEventListener("phx:open-settings", this._listener)
      window.__hasOpenSettingsBridge = true
    },
    destroyed() {
      window.removeEventListener("phx:open-settings", this._listener)
      window.__hasOpenSettingsBridge = false
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

