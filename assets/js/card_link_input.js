// Autocomplete for `[Card Name]` links in the question textarea.
//
// While the caret sits behind an *open* bracket ("... [Monster Re|") the typed
// part is sent to the server (`suggest_cards`, debounced). The best match is
// shown in a listbox; Tab, Enter (or a click) writes "[Full Name]" into the
// text and sends `link_card`. Enter only does that while the list is open, else
// it is a line break as usual. A list is only ever acted on for the query it was
// made for: it is hidden as soon as the query changes, and answers for an older
// query are dropped.
//
// The server answers `suggest_cards` with {suggestions} at once, or with
// {suggestions: [], pending: true} when the names come later as a
// `card_links:suggestions` event {query, suggestions} (the card sources can be
// slow, so the page does not wait for them). The list lives in the element named by `data-suggestions`
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
    this.suggestionsFor = null // the query `suggestions` belongs to
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

    this.handleEvent("card_links:suggestions", ({query, suggestions}) => {
      if (query !== this.lastQuery) return // the player has typed on since
      this.suggestions = suggestions || []
      this.suggestionsFor = query
      this.active = 0
      this.render()
    })

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
    // the list of the old query must not be acted on (Tab, Enter) meanwhile
    this.hide()
    if (query === null || query.length < MIN_QUERY) return

    const seq = this.seq
    this.timer = setTimeout(() => {
      this.pushEvent("suggest_cards", {query}, reply => {
        if (seq !== this.seq) return
        this.suggestions = (reply && reply.suggestions) || []
        this.suggestionsFor = query
        this.active = 0
        this.render()
      })
    }, DEBOUNCE_MS)
  },

  keydown(e) {
    const shown =
      this.suggestions.length > 0 && !this.dismissed && this.suggestionsFor === this.lastQuery
    if (e.key === "]") {
      const open = openBracket(this.el.value, this.el.selectionStart)
      const typed = open && open.query.trim().toLowerCase()
      const current = this.suggestionsFor === this.lastQuery ? this.suggestions : []
      const match = typed && current.find(s => s.name.toLowerCase() === typed)
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
    } else if (e.key === "Enter" && !e.shiftKey && !e.ctrlKey && !e.altKey && !e.metaKey && !e.isComposing) {
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

  // Keeps the list in view: a virtual keyboard can leave no room under the
  // textarea, so the list opens above it when there is more room there,
  // else it is scrolled into view.
  place() {
    const list = this.list
    delete list.dataset.placement
    const vv = window.visualViewport
    const top = vv ? vv.offsetTop : 0
    const bottom = top + (vv ? vv.height : window.innerHeight)
    const box = this.el.getBoundingClientRect()
    const below = bottom - box.bottom
    const above = box.top - top
    if (list.offsetHeight > below && above > below) {
      list.dataset.placement = "top"
    } else if (list.offsetHeight > below) {
      list.scrollIntoView({block: "nearest"})
    }
  },

  render() {
    if (this.suggestions.length === 0 || this.dismissed) return this.hide(false)
    // placed when the list opens or its suggestions change, not on every arrow
    // key: no flipping above/below and no repeated scrolling while browsing it
    const place = this.list.hidden || this.placedFor !== this.suggestions
    this.placedFor = this.suggestions
    const items = this.suggestions.map((s, i) => {
      const li = document.createElement("li")
      li.id = `${this.list.id}-option-${i}`
      li.setAttribute("role", "option")
      li.setAttribute("aria-selected", i === this.active ? "true" : "false")
      li.className = "mq-suggestion"
      const name = document.createElement("span")
      name.textContent = s.name
      li.append(name)
      if (i === 0 && window.matchMedia("(pointer: coarse)").matches) {
        // no Tab key on most virtual keyboards: say what works
        const hint = document.createElement("span")
        hint.className = "mq-suggestion-tag"
        hint.textContent = "tap to insert"
        li.append(hint)
      }
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
    if (place) this.place()
    this.el.setAttribute("aria-expanded", "true")
    this.el.setAttribute("aria-activedescendant", `${this.list.id}-option-${this.active}`)
  },
}
