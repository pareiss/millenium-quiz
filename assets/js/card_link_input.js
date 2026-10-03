// Autocomplete for `[Card Name]` links in the question textarea.
//
// While the caret sits behind an *open* bracket ("... [Monster Re|") the typed
// part is sent to the server (`suggest_cards`, debounced). The best match is
// shown in a listbox; Tab (or a click) writes "[Full Name]" into the text and
// sends `link_card`. The list lives in the element named by `data-suggestions`
// (a `phx-update="ignore"` container, so LiveView patches leave it alone).
const DEBOUNCE_MS = 250
const MIN_QUERY = 2

// Returns {start, query} when the caret is inside an open bracket, else null.
// `start` is the index of the `[`. Open means: the last `[` before the caret,
// with no `]` and no line break between it and the caret.
export function openBracket(text, caret) {
  const before = text.slice(0, caret)
  const start = before.lastIndexOf("[")
  if (start === -1) return null
  const query = before.slice(start + 1)
  if (query.includes("]") || query.includes("\n")) return null
  return {start, query}
}

export const CardLinkInput = {
  mounted() {
    this.list = document.getElementById(this.el.dataset.suggestions)
    this.seq = 0 // answers older than the latest request are dropped
    this.timer = null
    this.suggestions = []
    this.active = 0
    this.lastQuery = null
    this.dismissed = false

    this.onInput = () => this.update()
    this.onCaret = () => this.update()
    this.onBlur = () => this.hide()
    this.onKeydown = e => this.keydown(e)
    this.el.addEventListener("input", this.onInput)
    this.el.addEventListener("click", this.onCaret)
    this.el.addEventListener("keyup", e => {
      // only caret moves re-evaluate; Up/Down/Tab/Escape belong to the list
      if (["ArrowLeft", "ArrowRight", "Home", "End"].includes(e.key)) this.update()
    })
    this.el.addEventListener("keydown", this.onKeydown)
    this.el.addEventListener("blur", this.onBlur)

    this.handleEvent("card_links:set_text", ({text}) => {
      const old = this.el.value
      const caret = this.el.selectionStart
      this.el.value = text
      const pos = Math.max(0, Math.min(text.length, caret - (old.length - text.length)))
      this.el.setSelectionRange(pos, pos)
      this.hide()
    })
  },

  destroyed() {
    clearTimeout(this.timer)
    this.el.removeEventListener("input", this.onInput)
    this.el.removeEventListener("click", this.onCaret)
    this.el.removeEventListener("keydown", this.onKeydown)
    this.el.removeEventListener("blur", this.onBlur)
  },

  update() {
    const open = openBracket(this.el.value, this.el.selectionStart)
    const query = open ? open.query.trim() : null
    if (query === this.lastQuery) return
    this.lastQuery = query
    this.dismissed = false
    clearTimeout(this.timer)
    this.seq++ // invalidates answers still on their way
    if (query === null || query.length < MIN_QUERY) return this.hide()

    const seq = this.seq
    this.timer = setTimeout(() => {
      this.pushEvent("suggest_cards", {query}, reply => {
        if (seq !== this.seq) return
        this.suggestions = (reply && reply.suggestions) || []
        this.active = 0
        this.render()
      })
    }, DEBOUNCE_MS)
  },

  keydown(e) {
    const shown = this.suggestions.length > 0 && !this.dismissed
    if (e.key === "]") {
      const open = openBracket(this.el.value, this.el.selectionStart)
      const typed = open && open.query.trim().toLowerCase()
      const match = typed && this.suggestions.find(s => s.name.toLowerCase() === typed)
      if (match) {
        e.preventDefault()
        this.accept(match)
      }
      return
    }
    if (!shown) return
    if (e.key === "Tab" && !e.shiftKey) {
      e.preventDefault()
      this.accept(this.suggestions[this.active])
    } else if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault()
      const n = this.suggestions.length
      this.active = (this.active + (e.key === "ArrowDown" ? 1 : n - 1)) % n
      this.render()
    } else if (e.key === "Escape") {
      e.preventDefault()
      this.dismissed = true
      this.hide(false)
    }
  },

  accept(s) {
    const open = openBracket(this.el.value, this.el.selectionStart)
    if (!open) return this.hide()
    const text = this.el.value
    const caret = this.el.selectionStart
    // an existing `]` right behind the caret is reused, not doubled
    const end = text[caret] === "]" ? caret + 1 : caret
    const link = `[${s.name}]`
    const next = text.slice(0, open.start) + link + text.slice(end)
    const max = this.el.maxLength
    if (max > 0 && next.length > max) return this.hide() // no room: leave the text alone

    this.el.value = next
    const pos = open.start + link.length
    this.el.setSelectionRange(pos, pos)
    this.el.dispatchEvent(new Event("input", {bubbles: true})) // phx-change + counters
    this.hide()
    this.lastQuery = null

    // always sent: the server ignores a card that is already attached, and a
    // retry after a failed or dropped import must still go through
    this.pushEvent("link_card", s.source === "remote" ? {password: String(s.password)} : {id: String(s.id)})
  },

  hide(reset = true) {
    if (reset) this.suggestions = []
    this.list.hidden = true
    this.list.replaceChildren()
    this.el.setAttribute("aria-expanded", "false")
    this.el.removeAttribute("aria-activedescendant")
  },

  render() {
    if (this.suggestions.length === 0 || this.dismissed) return this.hide(false)
    const items = this.suggestions.map((s, i) => {
      const li = document.createElement("li")
      li.id = `${this.list.id}-option-${i}`
      li.setAttribute("role", "option")
      li.setAttribute("aria-selected", i === this.active ? "true" : "false")
      li.className = "mq-suggestion"
      const name = document.createElement("span")
      name.textContent = s.name
      li.append(name)
      if (s.source === "remote") {
        const tag = document.createElement("span")
        tag.className = "mq-suggestion-tag"
        tag.textContent = "import"
        li.append(tag)
      }
      // mousedown keeps the textarea focused; the click then accepts
      li.addEventListener("mousedown", e => e.preventDefault())
      li.addEventListener("click", () => this.accept(s))
      return li
    })
    this.list.replaceChildren(...items)
    this.list.hidden = false
    this.el.setAttribute("aria-expanded", "true")
    this.el.setAttribute("aria-activedescendant", `${this.list.id}-option-${this.active}`)
  },
}
