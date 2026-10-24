// Keeps the screen awake while a game is running (hot-seat play on a phone
// that would otherwise sleep between turns). `data-active="true"` asks for the
// lock; paused and finished games let it go. The browser drops the lock when
// the tab is hidden, so it is requested again when the page is visible. Without
// support, HTTPS or permission nothing happens.
export const WakeLock = {
  mounted() {
    this.lock = null
    this.onVisible = () => { if (document.visibilityState === "visible") this.sync() }
    document.addEventListener("visibilitychange", this.onVisible)
    this.sync()
  },
  updated() { this.sync() },
  destroyed() {
    document.removeEventListener("visibilitychange", this.onVisible)
    this.release()
  },
  sync() {
    if (this.el.dataset.active === "true") this.request()
    else this.release()
  },
  async request() {
    if (this.lock || this.pending || !("wakeLock" in navigator)) return
    this.pending = true
    try {
      const lock = await navigator.wakeLock.request("screen")
      this.pending = false
      // released or unmounted while the request was pending
      if (this.el.dataset.active !== "true" || !this.el.isConnected) return lock.release().catch(() => {})
      this.lock = lock
      lock.addEventListener("release", () => { if (this.lock === lock) this.lock = null })
    } catch (_e) {
      this.pending = false
    }
  },
  release() {
    const lock = this.lock
    this.lock = null
    if (lock) lock.release().catch(() => {})
  },
}
