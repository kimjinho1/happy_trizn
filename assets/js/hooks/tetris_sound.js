// Tetris 사운드 시스템 — WebAudio API 기반 절차적 효과음.
//
// 외부 mp3/wav 파일 없이 oscillator + envelope 로 합성.
// 게임 LiveView 가 phx:tetris-sfx 이벤트 보내면 매핑된 효과음 재생.
//
// 옵션 (data-* attribute):
//   - data-sound-volume: 0~100 (마스터 볼륨)
//   - data-sound-rotate / data-sound-line-clear / data-sound-tetris /
//     data-sound-b2b / data-sound-garbage / data-sound-top-out /
//     data-sound-countdown / data-sound-lock — 각 "true"/"false"
//
// 보내는 이벤트 이름:
//   rotate / lock / line_clear / tetris / b2b / garbage / top_out / countdown
//
// 디자인:
//   - 첫 사용자 입력 (keydown / click) 후 AudioContext resume
//     (브라우저 autoplay policy 우회).
//   - hook updated() 에서 옵션 매번 재파싱.

const SFX_DEFS = {
  // [type, freq Hz, duration ms, gain peak]
  rotate: { type: "square", freq: 480, duration: 70, gain: 0.18 },
  lock: { type: "sine", freq: 220, duration: 90, gain: 0.22 },
  line_clear: { type: "triangle", freq: 660, duration: 200, gain: 0.28 },
  tetris: { type: "sawtooth", freq: 880, duration: 380, gain: 0.32 },
  b2b: { type: "triangle", freq: 1040, duration: 320, gain: 0.30 },
  garbage: { type: "square", freq: 140, duration: 220, gain: 0.30 },
  top_out: { type: "sawtooth", freq: 110, duration: 600, gain: 0.34 },
  countdown: { type: "sine", freq: 720, duration: 140, gain: 0.20 },
}

function eventToOption(evt) {
  // event 이름 → data attribute camelCase.
  switch (evt) {
    case "rotate": return "soundRotate"
    case "lock": return "soundLock"
    case "line_clear": return "soundLineClear"
    case "tetris": return "soundTetris"
    case "b2b": return "soundB2b"
    case "garbage": return "soundGarbage"
    case "top_out": return "soundTopOut"
    case "countdown": return "soundCountdown"
    default: return null
  }
}

export const TetrisSound = {
  mounted() {
    this.parseDataset()
    this._unlock = () => this.unlockAudio()
    window.addEventListener("keydown", this._unlock, { once: true })
    window.addEventListener("click", this._unlock, { once: true })

    this.handleEvent("tetris:sfx", ({ event }) => this.play(event))
  },

  updated() {
    this.parseDataset()
  },

  destroyed() {
    window.removeEventListener("keydown", this._unlock)
    window.removeEventListener("click", this._unlock)
    if (this.ctx) {
      try { this.ctx.close() } catch (_e) { /* ignore */ }
      this.ctx = null
    }
  },

  parseDataset() {
    const ds = this.el.dataset
    this.masterVolume = clampVolume(parseInt(ds.soundVolume || "16", 10))
    // 각 효과음 enabled (data-sound-rotate 등). 기본 true.
    this.enabled = {}
    for (const evt of Object.keys(SFX_DEFS)) {
      const optKey = eventToOption(evt)
      const raw = optKey && ds[optKey]
      // data attribute 없으면 default true.
      this.enabled[evt] = raw === undefined || raw === null ? true : raw === "true"
    }
  },

  unlockAudio() {
    if (this.ctx) return
    try {
      const Ctor = window.AudioContext || window.webkitAudioContext
      if (!Ctor) return
      this.ctx = new Ctor()
    } catch (_e) {
      // unsupported browser
    }
  },

  play(event) {
    if (!this.ctx) return
    if (!this.enabled[event]) return

    const def = SFX_DEFS[event]
    if (!def) return

    const now = this.ctx.currentTime
    const osc = this.ctx.createOscillator()
    const gainNode = this.ctx.createGain()
    osc.type = def.type
    osc.frequency.setValueAtTime(def.freq, now)

    // 빠른 attack + 자연스러운 decay envelope. 마스터 볼륨 0~100% 비례.
    const peak = (def.gain * this.masterVolume) / 100
    const durationSec = def.duration / 1000
    gainNode.gain.setValueAtTime(0, now)
    gainNode.gain.linearRampToValueAtTime(peak, now + 0.01)
    gainNode.gain.exponentialRampToValueAtTime(0.0001, now + durationSec)

    osc.connect(gainNode)
    gainNode.connect(this.ctx.destination)
    osc.start(now)
    osc.stop(now + durationSec + 0.02)
  },
}

function clampVolume(v) {
  if (Number.isNaN(v)) return 16
  return Math.max(0, Math.min(100, v))
}
