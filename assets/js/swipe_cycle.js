// Swipe left/right on the open card view to step through a question's cards.
// The event name comes from `data-cycle-event`; mostly vertical gestures
// (scrolling the text panel) are ignored.
const THRESHOLD = 40

export const SwipeCycle = {
  mounted() {
    this.start = null
    this.onStart = e => {
      const t = e.touches[0]
      this.start = e.touches.length === 1 ? {x: t.clientX, y: t.clientY} : null
    }
    this.onEnd = e => {
      if (!this.start) return
      const t = e.changedTouches[0]
      const dx = t.clientX - this.start.x
      const dy = t.clientY - this.start.y
      this.start = null
      if (Math.abs(dx) < THRESHOLD || Math.abs(dx) < Math.abs(dy) * 1.5) return
      this.pushEvent(this.el.dataset.cycleEvent || "cycle_card", {dir: dx < 0 ? "next" : "prev"})
    }
    this.el.addEventListener("touchstart", this.onStart, {passive: true})
    this.el.addEventListener("touchend", this.onEnd, {passive: true})
  },
  destroyed() {
    this.el.removeEventListener("touchstart", this.onStart)
    this.el.removeEventListener("touchend", this.onEnd)
  },
}
