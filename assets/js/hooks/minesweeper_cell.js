// MinesweeperCell — 우클릭으로 flag 토글.
// 좌클릭은 phx-click 이 reveal 처리. 우클릭만 contextmenu 캐치 → pushEvent flag.
//
// 사용:
//   <button phx-hook="MinesweeperCell" id="ms-r-c" data-r="3" data-c="5" ...>

export const MinesweeperCell = {
  mounted() {
    this._oncontext = (e) => {
      e.preventDefault()
      const r = parseInt(this.el.dataset.r, 10)
      const c = parseInt(this.el.dataset.c, 10)
      this.pushEvent("input", { action: "flag", r: r, c: c })
    }
    this.el.addEventListener("contextmenu", this._oncontext)
  },

  destroyed() {
    this.el.removeEventListener("contextmenu", this._oncontext)
  },
}
