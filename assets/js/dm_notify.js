// DM 알림 — server LV 가 push_event("dm:notify", payload) 보낸 거 받음.
// side-effect import (app.js 에서 import 하면 즉시 listener 등록).
//
// 실행:
// 1. WebAudio "ding" 단조 톤.
// 2. 우상단 toast (4초).
// 3. 페이지 타이틀 (N) prefix 깜빡 (focus 받으면 stop).
// 4. 헤더 💬 옆 badge text 동적 갱신.

function playDing() {
  try {
    const Ctx = window.AudioContext || window.webkitAudioContext
    if (!Ctx) return
    const ctx = new Ctx()
    const osc = ctx.createOscillator()
    const gain = ctx.createGain()
    osc.connect(gain)
    gain.connect(ctx.destination)
    osc.type = "sine"
    osc.frequency.setValueAtTime(880, ctx.currentTime)
    osc.frequency.exponentialRampToValueAtTime(1320, ctx.currentTime + 0.08)
    gain.gain.setValueAtTime(0.0001, ctx.currentTime)
    gain.gain.exponentialRampToValueAtTime(0.18, ctx.currentTime + 0.02)
    gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.4)
    osc.start()
    osc.stop(ctx.currentTime + 0.45)
    osc.onended = () => ctx.close()
  } catch (_) {
    /* AudioContext 못 잡거나 user gesture 전이면 silent */
  }
}

function badgeText(count) {
  if (count > 300) return "300+"
  return String(count)
}

function updateBadge(count) {
  // 모든 unread badge — top nav 의 동적 1개 외에 다른 곳도 있을 수 있음.
  const link = document.querySelector('a[href="/dm"]')
  if (!link) return
  let badge = link.querySelector(".dm-unread-badge")
  if (count <= 0) {
    if (badge) badge.remove()
    return
  }
  if (!badge) {
    badge = document.createElement("span")
    badge.className = "badge badge-error badge-xs absolute -top-1 -right-1 dm-unread-badge"
    link.appendChild(badge)
  }
  badge.textContent = badgeText(count)
}

function showToast(text, href) {
  let el = document.getElementById("dm-toast")
  if (!el) {
    el = document.createElement("div")
    el.id = "dm-toast"
    el.className =
      "fixed top-16 right-4 z-50 max-w-xs bg-base-100 border border-primary/40 shadow-xl rounded-lg p-3 text-sm cursor-pointer transition-opacity duration-300"
    el.style.opacity = "0"
    document.body.appendChild(el)
  }
  el.textContent = text
  el.onclick = () => { window.location.href = href || "/dm" }
  // 약간 딜레이 후 opacity 1 → fade in 효과.
  requestAnimationFrame(() => { el.style.opacity = "1" })
  clearTimeout(el._fadeTimer)
  el._fadeTimer = setTimeout(() => { el.style.opacity = "0" }, 4000)
}

let _titleTimer
let _origTitle
function flashTitle(count) {
  if (!_origTitle) _origTitle = document.title.replace(/^\(\d+\) /, "")
  if (count <= 0) {
    if (_titleTimer) clearInterval(_titleTimer)
    document.title = _origTitle
    return
  }
  if (_titleTimer) clearInterval(_titleTimer)
  let toggle = false
  _titleTimer = setInterval(() => {
    document.title = toggle ? _origTitle : `(${count}) ${_origTitle}`
    toggle = !toggle
  }, 1500)
  // focus 잡으면 stop + 원복.
  const onFocus = () => {
    if (_titleTimer) { clearInterval(_titleTimer); _titleTimer = null }
    document.title = _origTitle
    window.removeEventListener("focus", onFocus)
  }
  window.addEventListener("focus", onFocus)
}

window.addEventListener("phx:dm:notify", (e) => {
  const { body = "", unread_count = 0, from_user_id } = e.detail || {}
  updateBadge(unread_count)
  playDing()
  const href = from_user_id ? `/dm/${from_user_id}` : "/dm"
  showToast(`💬 ${body || "새 메시지"}`, href)
  flashTitle(unread_count)
})
