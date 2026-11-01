defmodule MillenniumQuizWeb.DuelComponents do
  @moduledoc """
  Building blocks of the opt-in "duel" look (5D's / Neo Domino): the life point
  gauge, the ATK label, the Synchro ring and the question progress rail.

  Their CSS is in `assets/css/app.css` and uses the daisyUI colours, so they look
  right in every theme; the duel themes `duel-dark` and `duel-light` add the cut
  corners, the segmented bar, Orbitron and the glow. Names, numbers and status are
  real text. The game screens (`GameLive`) use them.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  import MillenniumQuizWeb.CoreComponents, only: [avatar: 1, icon: 1]

  @doc """
  A player's life point gauge: avatar, name, the LP number on a plate (with
  leading zeros), a depleting bar and, after a hit, a ghost of the lost part.

  One markup for every width: the wrapper is a container, and the CSS rearranges
  it at 420px and wider (wide), 300 to 419px (compact), below 300px (mini) and below
  100px (tight: number and bar only, the name stays for screen readers).

  The state is never shown by colour alone: a hit shows its damage as text, an
  eliminated player shows "K.O." and a grey, empty bar, the active player has a
  Synchro ring around the avatar and `aria-current`.
  """
  attr :id, :string, default: nil
  attr :lp_id, :string, default: nil, doc: "the id of the number (its text is the LP)"
  attr :bar_id, :string, default: nil, doc: "the id of the bar, a progress bar of the LP"
  attr :name, :string, required: true
  attr :avatar, :string, default: nil, doc: "the avatar slug"
  attr :crop, :map, default: nil, doc: "the avatar's crop, see `CoreComponents.avatar/1`"
  attr :lp, :integer, required: true
  attr :start_lp, :integer, required: true
  attr :player, :integer, default: 0, doc: "0..3, picks the colour --duel-p1..p4"
  attr :status, :atom, default: :alive, values: [:alive, :hit, :eliminated]
  attr :damage, :integer, default: nil, doc: "the amount just lost (the ghost segment)"
  attr :active, :boolean, default: false, doc: "the current chooser or answerer"
  attr :class, :any, default: nil

  def lp_gauge(assigns) do
    lp = max(assigns.lp, 0)
    start = max(assigns.start_lp, 1)
    # 0 LP is K.O., whatever the caller passed (a player knocked out by this
    # very hit arrives as :hit); the ghost still shows the final hit
    status = if lp == 0, do: :eliminated, else: assigns.status
    damage = if assigns.damage && assigns.damage > 0, do: assigns.damage, else: nil
    # a living player always shows a sliver of bar
    lp_pct = if lp > 0, do: max(pct(lp, start), 3.0), else: 0.0

    assigns =
      assigns
      |> assign(:status, status)
      |> assign(:player, assigns.player |> max(0) |> min(3))
      |> assign(:number, number(lp, start))
      |> assign(:lp_value, lp)
      |> assign(:lp_pct, lp_pct)
      |> assign(:damage, damage)
      |> assign(:ghost_pct, damage && min(pct(damage, start), 100 - lp_pct))

    ~H"""
    <div
      id={@id}
      class={["duel-gauge", @class]}
      data-player={@player + 1}
      data-status={@status}
      data-active={to_string(@active)}
    >
      <div class="duel-gauge-body" aria-current={@active && "true"}>
        <div class="duel-gauge-avatar">
          <.synchro_ring :if={@active} class="size-full">
            <.avatar slug={@avatar} crop={@crop} title={@name} class="size-full !ring-0" />
          </.synchro_ring>
          <span :if={!@active} class="duel-gauge-avatar-plain">
            <.avatar slug={@avatar} crop={@crop} title={@name} class="size-full !ring-0" />
          </span>
        </div>
        <span class="duel-gauge-name" title={@name}>{@name}</span>
        <div class="duel-gauge-plate">
          <span class="duel-gauge-lp-label" aria-hidden="true">LP</span>
          <span
            id={@lp_id}
            class="duel-gauge-num"
            data-lp={@lp_value}
            phx-hook={@lp_id && "MillenniumQuizWeb.DuelComponents.LpCount"}
          ><span
            :if={@number.zeros != ""}
            class="duel-gauge-zeros"
          >{@number.zeros}</span>{@number.digits}</span>
          <span :if={@status == :eliminated} class="duel-gauge-ko">
            <span aria-hidden="true">✕</span> K.O.
          </span>
          <span :if={@status == :hit and @damage} class="duel-gauge-dmg">
            <span aria-hidden="true">▼</span> −{@damage}
          </span>
          <span :if={@status == :hit and !@damage} class="duel-gauge-dmg">
            <span aria-hidden="true">▼</span> HIT
          </span>
        </div>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".LpCount">
          // The LP number counts down when it drops (the text is already the new value for
          // anyone who cannot see it: this only draws the steps in between), unless the
          // visitor prefers reduced motion. It never holds an update back.
          export default {
            mounted() { this.last = Number(this.el.dataset.lp) },
            updated() {
              const to = Number(this.el.dataset.lp), from = this.last
              this.last = to
              if (!(to < from) || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
              const html = this.el.innerHTML
              const width = this.el.textContent.length
              const start = performance.now(), span = 700
              if (this.frame) cancelAnimationFrame(this.frame)
              const step = (now) => {
                const t = Math.min(1, (now - start) / span)
                if (t >= 1) { this.el.innerHTML = html; this.frame = null; return }
                const v = Math.round(from + (to - from) * (1 - Math.pow(1 - t, 3)))
                this.el.textContent = String(v).padStart(width, "0")
                this.frame = requestAnimationFrame(step)
              }
              step(start)
            },
            destroyed() { if (this.frame) cancelAnimationFrame(this.frame) }
          }
        </script>
        <div
          id={@bar_id}
          class="duel-gauge-bar"
          role="progressbar"
          aria-label={"#{@name}'s life points"}
          aria-valuemin="0"
          aria-valuemax={@start_lp}
          aria-valuenow={@lp_value}
        >
          <div class="duel-gauge-fill" style={"width:#{@lp_pct}%"}></div>
          <div
            :if={@ghost_pct && @ghost_pct > 0}
            class="duel-gauge-ghost"
            style={"left:#{@lp_pct}%;width:#{@ghost_pct}%"}
          >
          </div>
        </div>
      </div>
    </div>
    """
  end

  # 0..100, one decimal
  defp pct(value, total), do: min(Float.round(value * 100 / total, 1), 100.0)

  # "04000": at least 5 digits, or the digits of the start LP if more
  defp number(lp, start) do
    width = max(5, start |> Integer.to_string() |> String.length())
    text = lp |> Integer.to_string() |> String.pad_leading(width, "0")
    digits = Integer.to_string(lp)
    zeros = String.slice(text, 0, String.length(text) - String.length(digits))
    %{zeros: zeros, digits: digits}
  end

  @doc """
  The red "ATK" pill, optionally in front of a value (a damage number).

  ## Examples

      <.atk_label value="1600" />
  """
  attr :value, :any, default: nil
  attr :class, :any, default: nil

  def atk_label(assigns) do
    ~H"""
    <span class={["duel-atk", @class]}>
      <span class="duel-atk-pill">ATK</span>
      <span :if={@value != nil} class="duel-atk-value">{@value}</span>
    </span>
    """
  end

  @doc """
  The Synchro ring: 12 identical dashes around its content (an avatar), the
  turn marker. The ring shape is the `<symbol id="duel-ring">` of the root layout.
  The ring sizes with its parent: give it a class like `size-14`.
  """
  attr :class, :any, default: "size-14"
  slot :inner_block

  def synchro_ring(assigns) do
    ~H"""
    <span class={["duel-ring relative inline-block shrink-0", @class]}>
      <svg
        viewBox="0 0 64 64"
        class="duel-ring-svg absolute inset-0 size-full overflow-visible"
        aria-hidden="true"
        focusable="false"
      >
        <use href="#duel-ring" />
      </svg>
      <span class="duel-ring-inner absolute inset-[13%] overflow-hidden rounded-full">
        {render_slot(@inner_block)}
      </span>
    </span>
    """
  end

  @doc """
  The question progress rail: `total` slanted blocks, the answered ones filled,
  the current one a glowing orb, the rest dim. The blocks are decorative; the
  rail is a progress bar with a text value for screen readers.
  """
  attr :id, :string, default: nil
  attr :total, :integer, required: true
  attr :current, :integer, required: true, doc: "1-based number of the current question"
  attr :label, :string, default: "Question"
  attr :class, :any, default: nil

  def orb_rail(assigns) do
    total = max(assigns.total, 1)
    current = assigns.current |> max(1) |> min(total)
    assigns = assigns |> assign(:total, total) |> assign(:current, current)

    ~H"""
    <div
      id={@id}
      class={["duel-rail", @class]}
      style={"--n:#{@total}"}
      role="progressbar"
      aria-valuemin="1"
      aria-valuemax={@total}
      aria-valuenow={@current}
      aria-valuetext={"#{@label} #{@current} of #{@total}"}
      aria-label={@label}
    >
      <span
        :for={n <- 1..@total}
        class="duel-rail-block"
        data-state={block_state(n, @current)}
        aria-hidden="true"
      ></span>
    </div>
    """
  end

  defp block_state(n, current) when n < current, do: "answered"
  defp block_state(n, current) when n == current, do: "current"
  defp block_state(_n, _current), do: "upcoming"

  # ---------------------------------------------------------------------------
  # The board view (read only)
  # ---------------------------------------------------------------------------

  @phases %{
    "draw" => "Draw Phase",
    "standby" => "Standby Phase",
    "main1" => "Main Phase 1",
    "battle" => "Battle Phase",
    "main2" => "Main Phase 2",
    "end" => "End Phase"
  }

  @doc """
  The "Board" button of a question that has a board: an icon, the word "Board"
  and a line that says what is on the board before it is opened, for example
  "Turn 3 · Main Phase 1 / 5 cards on the field". `on_click` is an event name or
  a `Phoenix.LiveView.JS` command that opens the dialog (the caller owns that
  state).
  """
  attr :id, :string, default: "board-button"
  attr :board, :map, required: true, doc: "see `duel_board/1`"
  attr :on_click, :any, required: true
  attr :class, :any, default: nil

  def board_button(assigns) do
    assigns = assign(assigns, :summary, board_summary(assigns.board))

    ~H"""
    <div class={["duel-board-entry", @class]}>
      <button
        type="button"
        id={@id}
        class="btn btn-outline btn-primary min-h-11"
        phx-click={@on_click}
        aria-haspopup="dialog"
        aria-describedby={"#{@id}-note"}
      >
        <.icon name="hero-table-cells" class="size-5" /> Board
      </button>
      <small id={"#{@id}-note"} class="duel-board-note">
        <span :if={@summary.turn} class="block">{@summary.turn}</span>
        <span class="block">{@summary.cards}</span>
      </small>
    </div>
    """
  end

  defp board_summary(board) do
    turn =
      [turn_text(board["turn"]), @phases[board["phase"]]]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

    n = field_count(board)

    %{
      turn: if(turn == "", do: nil, else: turn),
      cards: if(n == 1, do: "1 card on the field", else: "#{n} cards on the field")
    }
  end

  defp turn_text(nil), do: nil
  defp turn_text(n), do: "Turn #{n}"

  # cards in the zones of the field (not hand, graveyard, banished or Extra Deck)
  defp field_count(board) do
    on_field =
      Enum.flat_map(board["players"] || [], fn p ->
        (p["monsters"] || []) ++ (p["spells"] || []) ++ [p["field"]]
      end)

    emz = if board["rule"] == "mr4", do: board["emz"] || [], else: []
    Enum.count(on_field ++ emz, &(&1 != nil))
  end

  @doc """
  The board of a question in a dialog: Player 2 on top, Player 1 at the bottom,
  each side with its colour edge, name, "Player N" and life points; per side the
  field spell zone beside four chips (Deck, Extra, Grave, Banish), 5 spell/trap
  zones and 5 monster zones; the two shared Extra Monster Zones between the sides
  only for the Master Rule 4 (`"mr4"`); a row of small tiles for a hand that has
  cards. Read only: nothing here changes the game.

  The caller owns the open state: render this component while the dialog is open.
  It is a modal dialog (focus goes to the close button, Escape and the backdrop
  send `on_close`). The Deck chip only shows a count; the Extra, Grave and Banish
  chips open a list sheet of mini tiles when they hold cards and are dimmed and
  inert at 0. The list sheets open and close in the browser (`Phoenix.LiveView.JS`).

  From 900px the `:detail` slot is shown in a panel beside the board (for the
  selected card); below that the caller shows the existing card dialog instead.

  ## The board

  A map with string keys (what B2 resolves from the stored JSON):

      %{
        "rule" => "mr1_2" | "mr3" | "mr4",
        "turn" => 3 | nil,
        "phase" => "draw" | "standby" | "main1" | "battle" | "main2" | "end" | nil,
        "turn_player" => 1 | 2 | nil,
        "emz" => [card | nil, card | nil],      # only drawn when "rule" == "mr4"
        "reveal_all" => false,                  # optional, see below
        "players" => [player1, player2]
      }

  and per player:

      %{
        "lp" => 8000,
        "name" => nil,                         # the component takes the names as an attr
        "monsters" => [card | nil] x 5,
        "spells" => [card | nil] x 5,          # a Pendulum scale sits in 0 and 4 ("scale" => true)
        "field" => card | nil,
        "hand" => [card], "grave" => [card], "banished" => [card], "extra" => [card],
        "deck" => 25                           # a count
      }

  and a card:

      %{
        "name" => "Jinzo", "password" => 77585513,
        "kind" => "normal" | "effect" | "fusion" | "ritual" | "synchro" | "xyz" |
                  "link" | "pendulum" | "spell" | "trap",
        "atk" => 2400 | nil, "def" => 1500 | nil, "level" => 6 | nil,
        "pos" => "atk" | "def" | "set",        # "set" = face down
        "overlay" => 0, "counters" => 0,       # Xyz materials, counters in total
        "art" => "/images/avatars/jinzo.jpg" | nil,
        "scale" => false
      }

  Face-down cards (`"pos" => "set"`) are always drawn as the card back. A face-down
  card of Player 1 can be tapped like a face-up one (`on_card` is sent, its label
  names the card and says "face-down"), so the caller may show its details. A
  face-down card of Player 2 is an inert picture (not a button, no `on_card`, label
  "Face-down card, ...") unless the board has `"reveal_all" => true` (a boolean,
  missing means false; used by puzzles): then every face-down card behaves like
  Player 1's.

  Cards in a hand, graveyard, banished zone or Extra Deck have `"pos" => "atk"`
  and only name, kind, atk, def and art matter.

  ## Events

  `on_card` is sent when a tile (or a list item) is tapped, with
  `phx-value-key` (`"p1:monsters:2"`, `"emz:0"`, `"p2:grave:1"`: player, zone and
  0-based index; the same string is what `selected` takes), `phx-value-player`
  ("1" or "2", not set for an Extra Monster Zone), `phx-value-zone` (`"monsters"`,
  `"spells"`, `"field"`, `"hand"`, `"grave"`, `"banished"`, `"extra"`, `"emz"`)
  and `phx-value-index`. Without `on_card` the tiles are buttons that do nothing. Tile ids look like
  `board-dialog-tile-p1-monsters-2` (the dialog id, `-tile-`, the key).
  """
  attr :id, :string, default: "board-dialog"
  attr :board, :map, required: true
  attr :names, :map, default: %{}, doc: "%{1 => \"Mika\", 2 => \"Tobias\"}"
  attr :on_close, :any, required: true
  attr :on_card, :string, default: nil
  attr :selected, :string, default: nil, doc: "the key of the highlighted tile"
  attr :start_lp, :integer, default: 8000, doc: "what a full life point bar is"
  slot :detail, doc: "the selected card, shown in the panel from 900px"

  def duel_board(assigns) do
    board = assigns.board
    [p1, p2] = board["players"]

    assigns =
      assigns
      |> assign(:rule, board["rule"])
      |> assign(:reveal_all, board["reveal_all"] == true)
      |> assign(:p1, p1)
      |> assign(:p2, p2)
      |> assign(:emz, for(i <- 0..1, do: Enum.at(board["emz"] || [], i)))
      |> assign(:subtitle, subtitle(board, assigns.names))
      |> assign(:sheets, sheets(board["players"], assigns.names))

    ~H"""
    <div
      id={@id}
      class="mq-dialog duel-board-dialog fixed inset-0 z-50 overflow-y-auto"
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      phx-hook=".BoardDialog"
      phx-window-keydown={@on_close}
      phx-key="escape"
      phx-mounted={JS.focus(to: "##{@id}-close")}
    >
      <script :type={Phoenix.LiveView.ColocatedHook} name=".BoardDialog">
        // Escape closes an open list sheet first, by running the sheet's own close command
        // (so LiveView's show/hide state stays right); only without a sheet it reaches the
        // dialog's own Escape binding, which closes the board. The listener is on the
        // document, in the capture phase, so it runs before LiveView's. It stands back when
        // another dialog (the card dialog) is open above the board, so that one gets Escape.
        export default {
          mounted() {
            this.onKey = (event) => {
              if (event.key !== "Escape") return
              const sheet = [...this.el.querySelectorAll(".duel-sheet")]
                .find((el) => getComputedStyle(el).display !== "none")
              if (!sheet) return
              const above = [...document.querySelectorAll(".mq-dialog")]
                .some((el) => el !== this.el && !this.el.contains(el))
              if (above) return
              const btn = sheet.querySelector(".duel-board-close")
              event.stopPropagation()
              event.preventDefault()
              this.liveSocket.execJS(btn, btn.getAttribute("phx-click"))
            }
            document.addEventListener("keydown", this.onKey, true)
          },
          destroyed() { document.removeEventListener("keydown", this.onKey, true) }
        }
      </script>
      <div class="duel-board-backdrop fixed inset-0 bg-black/85" phx-click={@on_close}></div>
      <div class="duel-board-sheet">
        <header class="duel-board-head">
          <div class="duel-board-title">
            <h2 id={"#{@id}-title"}>Board</h2>
            <span :if={@subtitle != ""}>{@subtitle}</span>
          </div>
          <button
            type="button"
            id={"#{@id}-close"}
            class="duel-board-close"
            phx-click={@on_close}
            aria-label="Close the board"
            title="Close"
          >
            <.icon name="hero-x-mark" class="size-6" />
          </button>
        </header>
        <div class="duel-board-body">
          <div class="duel-board-main">
            <div class="duel-board-mat">
              <.board_side
                id={@id}
                seat={2}
                player={@p2}
                name={Map.get(@names, 2, "Player 2")}
                turn?={@board["turn_player"] == 2}
                start_lp={@start_lp}
                reveal_all={@reveal_all}
                on_card={@on_card}
                selected={@selected}
              />
              <div
                :if={@rule == "mr4"}
                id={"#{@id}-emz"}
                class="duel-emz"
                role="group"
                aria-label="Extra Monster Zones"
              >
                <p class="duel-emz-label" aria-hidden="true">Extra Monster Zones</p>
                <div class="duel-zones">
                  <span class="duel-cell duel-cell-gap" aria-hidden="true"></span>
                  <.zone
                    card={Enum.at(@emz, 0)}
                    id={@id}
                    reveal_all={@reveal_all}
                    key="emz:0"
                    place="Extra Monster Zone 1"
                    emz
                    on_card={@on_card}
                    selected={@selected}
                    zone="emz"
                    index={0}
                  />
                  <span class="duel-cell duel-cell-gap" aria-hidden="true"></span>
                  <.zone
                    card={Enum.at(@emz, 1)}
                    id={@id}
                    reveal_all={@reveal_all}
                    key="emz:1"
                    place="Extra Monster Zone 2"
                    emz
                    on_card={@on_card}
                    selected={@selected}
                    zone="emz"
                    index={1}
                  />
                  <span class="duel-cell duel-cell-gap" aria-hidden="true"></span>
                </div>
              </div>
              <.board_side
                id={@id}
                seat={1}
                player={@p1}
                name={Map.get(@names, 1, "Player 1")}
                turn?={@board["turn_player"] == 1}
                start_lp={@start_lp}
                reveal_all={@reveal_all}
                on_card={@on_card}
                selected={@selected}
              />
            </div>
          </div>
          <aside class="duel-board-panel" aria-label="Selected card">
            {render_slot(@detail)}
            <p :if={@detail == []} class="duel-board-hint">Select a card to read it.</p>
          </aside>
        </div>
        <%!-- outside the mat: its container and the cut corners would hold a fixed sheet inside --%>
        <.stack_sheet
          :for={s <- @sheets}
          id={@id}
          seat={s.seat}
          name={s.name}
          zone={s.zone}
          noun={s.noun}
          cards={s.cards}
          on_card={@on_card}
          selected={@selected}
        />
      </div>
    </div>
    """
  end

  @stacks [{"extra", "Extra Deck"}, {"grave", "graveyard"}, {"banished", "banished cards"}]

  # one list sheet per stack that has cards, for both sides
  defp sheets([p1, p2], names) do
    for {seat, p} <- [{2, p2}, {1, p1}],
        {zone, noun} <- @stacks,
        cards = p[zone] || [],
        cards != [] do
      %{
        seat: seat,
        name: Map.get(names, seat, "Player #{seat}"),
        zone: zone,
        noun: noun,
        cards: cards
      }
    end
  end

  defp subtitle(board, names) do
    mover =
      case board["turn_player"] do
        seat when seat in [1, 2] -> "#{Map.get(names, seat, "Player #{seat}")} to move"
        _ -> nil
      end

    [turn_text(board["turn"]), @phases[board["phase"]], mover]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  attr :id, :string, required: true
  attr :seat, :integer, required: true
  attr :player, :map, required: true
  attr :name, :string, required: true
  attr :turn?, :boolean, default: false
  attr :start_lp, :integer, required: true
  attr :reveal_all, :boolean, default: false
  attr :on_card, :string, default: nil
  attr :selected, :string, default: nil

  # One side of the mat. The opponent (seat 2) is drawn with the stacks on top and
  # the monsters next to the middle; seat 1 the other way round, so the zones that
  # face each other are always next to each other.
  defp board_side(assigns) do
    p = assigns.player
    lp = max(p["lp"] || 0, 0)
    start = Enum.max([assigns.start_lp, lp, 1])

    assigns =
      assigns
      |> assign(:lp, lp)
      |> assign(:lp_start, start)
      |> assign(:blocks, if(lp > 0, do: max(round(10 * lp / start), 1), else: 0))
      |> assign(:top?, assigns.seat == 2)
      |> assign(:hand, p["hand"] || [])

    ~H"""
    <section
      id={"#{@id}-side-#{@seat}"}
      class="duel-side"
      data-seat={@seat}
      data-turn={to_string(@turn?)}
      aria-current={@turn? && "true"}
      aria-label={"Player #{@seat}, #{@name}"}
    >
      <div class="duel-side-head">
        <span class="duel-seat" aria-hidden="true">{@seat}</span>
        <h3 class="duel-side-name" title={@name}>
          <span class="duel-side-name-text">{@name}</span><small>Player {@seat}{if @turn?,
            do: " · turn"}</small>
        </h3>
        <div class="duel-lp">
          <span
            class="duel-lp-bar"
            role="progressbar"
            aria-label={"#{@name}'s life points"}
            aria-valuemin="0"
            aria-valuemax={@lp_start}
            aria-valuenow={@lp}
          >
            <u :for={n <- 1..10} class={n > @blocks && "off"}></u>
          </span>
          <span class="duel-lp-num" id={"#{@id}-lp-#{@seat}"}>{@lp}</span>
        </div>
      </div>

      <.board_hand
        :if={@top? and @hand != []}
        id={@id}
        seat={@seat}
        cards={@hand}
        reveal_all={@reveal_all}
        on_card={@on_card}
        selected={@selected}
      />
      <.board_stacks
        :if={@top?}
        id={@id}
        seat={@seat}
        player={@player}
        name={@name}
        reveal_all={@reveal_all}
        on_card={@on_card}
        selected={@selected}
      />
      <.board_row
        :if={@top?}
        kind="spells"
        seat={@seat}
        player={@player}
        id={@id}
        reveal_all={@reveal_all}
        on_card={@on_card}
        selected={@selected}
      />
      <.board_row
        kind="monsters"
        seat={@seat}
        player={@player}
        id={@id}
        reveal_all={@reveal_all}
        on_card={@on_card}
        selected={@selected}
      />
      <.board_row
        :if={!@top?}
        kind="spells"
        seat={@seat}
        player={@player}
        id={@id}
        reveal_all={@reveal_all}
        on_card={@on_card}
        selected={@selected}
      />
      <.board_stacks
        :if={!@top?}
        id={@id}
        seat={@seat}
        player={@player}
        name={@name}
        reveal_all={@reveal_all}
        on_card={@on_card}
        selected={@selected}
      />
      <.board_hand
        :if={!@top? and @hand != []}
        id={@id}
        seat={@seat}
        cards={@hand}
        reveal_all={@reveal_all}
        on_card={@on_card}
        selected={@selected}
      />
    </section>
    """
  end

  attr :kind, :string, required: true, values: ~w(monsters spells)
  attr :seat, :integer, required: true
  attr :player, :map, required: true
  attr :id, :string, required: true
  attr :reveal_all, :boolean, default: false
  attr :on_card, :string, default: nil
  attr :selected, :string, default: nil

  defp board_row(assigns) do
    cards = assigns.player[assigns.kind] || []
    assigns = assign(assigns, :cards, for(i <- 0..4, do: Enum.at(cards, i)))

    ~H"""
    <div class="duel-zones" data-row={@kind}>
      <.zone
        :for={{card, i} <- Enum.with_index(@cards)}
        card={card}
        id={@id}
        reveal_all={@reveal_all}
        key={"p#{@seat}:#{@kind}:#{i}"}
        place={place(@seat, @kind, i, card)}
        on_card={@on_card}
        selected={@selected}
        zone={@kind}
        player={@seat}
        index={i}
      />
    </div>
    """
  end

  defp place(seat, "monsters", i, _card), do: "Player #{seat} monster zone #{i + 1}"

  defp place(seat, "spells", i, %{"scale" => true}),
    do: "Player #{seat} Pendulum zone #{i + 1}"

  defp place(seat, "spells", i, _card), do: "Player #{seat} spell/trap zone #{i + 1}"

  attr :card, :map, default: nil
  attr :key, :string, required: true
  attr :place, :string, required: true
  attr :zone, :string, required: true
  attr :player, :integer, default: nil
  attr :index, :integer, required: true
  attr :emz, :boolean, default: false
  attr :id, :string, required: true
  attr :reveal_all, :boolean, default: false
  attr :on_card, :string, default: nil
  attr :selected, :string, default: nil

  # a zone: the dashed slot, with a tile in it when it holds a card
  defp zone(assigns) do
    ~H"""
    <div class="duel-cell" data-empty={to_string(@card == nil)} data-emz={to_string(@emz)}>
      <.tile_button
        :if={@card}
        card={@card}
        id={@id}
        reveal_all={@reveal_all}
        key={@key}
        place={@place}
        zone={@zone}
        player={@player}
        index={@index}
        on_card={@on_card}
        selected={@selected}
      />
    </div>
    """
  end

  attr :card, :map, required: true
  attr :id, :string, required: true
  attr :key, :string, required: true
  attr :place, :string, required: true
  attr :zone, :string, required: true
  attr :player, :integer, default: nil
  attr :index, :integer, required: true
  attr :reveal_all, :boolean, default: false
  attr :on_card, :string, default: nil
  attr :selected, :string, default: nil
  attr :variant, :string, default: "board", values: ~w(board hand)

  # A face-up card, any card of Player 1 and, with the board's "reveal_all", every card
  # is a button. A face-down card of Player 2 is an inert picture (its card back).
  defp tile_button(assigns) do
    reveal? = assigns.card["pos"] != "set" or assigns.player == 1 or assigns.reveal_all

    assigns =
      assigns
      |> assign(:reveal?, reveal?)
      |> assign(:label, tile_label(assigns.card, assigns.place, reveal?))
      |> assign(:dom_id, "#{assigns.id}-tile-#{String.replace(assigns.key, ":", "-")}")

    ~H"""
    <button
      :if={@reveal?}
      type="button"
      id={@dom_id}
      class="duel-tile-btn"
      data-selected={to_string(@selected == @key)}
      aria-current={@selected == @key && "true"}
      aria-label={@label}
      title={@card["name"]}
      phx-click={@on_card}
      phx-value-key={@key}
      phx-value-player={@player}
      phx-value-zone={@zone}
      phx-value-index={@index}
    >
      <.tile card={@card} variant={@variant} />
    </button>
    <div
      :if={!@reveal?}
      id={@dom_id}
      class="duel-tile-btn"
      data-inert="true"
      role="img"
      aria-label={@label}
    >
      <.tile card={@card} variant={@variant} />
    </div>
    """
  end

  attr :card, :map, required: true
  attr :variant, :string, default: "board", values: ~w(board hand list)

  # The face of a card: frame colour by kind, artwork (or the initial), name bar and
  # the ATK / DEF strip (red with a sword in attack position, blue with a shield and
  # the artwork turned in defense position). A face-down card is the card back.
  defp tile(assigns) do
    card = assigns.card

    assigns =
      assigns
      |> assign(:kind, card["kind"] || "effect")
      |> assign(:pos, card["pos"] || "atk")
      |> assign(:monster?, monster?(card))
      |> assign(:overlay, card["overlay"] || 0)
      |> assign(:counters, card["counters"] || 0)
      |> assign(:initial, initial(card))

    ~H"""
    <span
      class="duel-tile"
      data-kind={@kind}
      data-pos={@pos}
      data-monster={to_string(@monster?)}
      data-variant={@variant}
      data-scale={to_string(@card["scale"] == true)}
    >
      <span :if={@pos != "set" and @overlay > 0} class="duel-tile-badge" data-badge="overlay">
        <span class="sr-only">overlay units </span>×{@overlay}
      </span>
      <span :if={@pos != "set" and @counters > 0} class="duel-tile-badge" data-badge="counters">
        <span class="sr-only">counters </span>{@counters}
      </span>
      <span
        :if={@card["scale"] == true and @pos != "set"}
        class="duel-tile-badge"
        data-badge="scale"
      >
        PS
      </span>
      <span :if={@pos != "set"} class="duel-tile-art">
        <img
          :if={@card["art"]}
          src={@card["art"]}
          alt=""
          draggable="false"
          decoding="async"
          loading={if @variant == "list", do: "lazy", else: "eager"}
        />
        <span :if={!@card["art"]} class="duel-tile-initial" aria-hidden="true">{@initial}</span>
      </span>
      <span :if={@pos != "set" and @variant == "board"} class="duel-tile-name">
        {@card["name"]}
      </span>
      <span :if={@pos != "set" and @monster? and @variant == "board"} class="duel-tile-stat">
        <.sword_icon :if={@pos == "atk"} /><.shield_icon :if={@pos == "def"} />{stat_value(
          @card,
          @pos
        )}
      </span>
    </span>
    """
  end

  defp monster?(card), do: card["kind"] not in ["spell", "trap"]

  defp initial(card) do
    case String.trim(card["name"] || "") do
      "" -> "?"
      name -> name |> String.first() |> String.upcase()
    end
  end

  defp stat_value(card, "def"), do: stat(card["def"])
  defp stat_value(card, _), do: stat(card["atk"])

  defp stat(nil), do: "?"
  defp stat(n), do: n

  # The accessible name of a tile: "Jinzo, attack position, ATK 2400, Player 2 monster zone 2".
  # A face-down card the viewer may not see is just "Face-down card, place"; one that
  # may be revealed names the card and says it is face down.
  defp tile_label(%{"pos" => "set"}, place, false), do: "Face-down card, #{place}"

  defp tile_label(card, place, _reveal?) do
    down? = card["pos"] == "set"
    overlay = card["overlay"] || 0
    counters = card["counters"] || 0

    parts =
      case {card["pos"] || "atk", monster?(card)} do
        {"set", true} ->
          [card["name"], "face-down defense monster"]

        {"set", false} ->
          [card["name"], "face-down spell or trap card"]

        {"def", true} ->
          [card["name"], "defense position", "DEF #{stat(card["def"])}"]

        {_, true} ->
          [card["name"], "attack position", "ATK #{stat(card["atk"])}"]

        {_, false} ->
          [card["name"], if(card["kind"] == "spell", do: "Spell card", else: "Trap card")]
      end

    extra =
      if down? do
        []
      else
        if(card["scale"] == true, do: ["Pendulum Scale"], else: []) ++
          if(overlay > 0, do: ["#{overlay} overlay units"], else: []) ++
          if counters > 0, do: ["#{counters} counters"], else: []
      end

    Enum.join(parts ++ extra ++ [place], ", ")
  end

  # The stubby filled sword before an ATK value
  defp sword_icon(assigns) do
    ~H"""
    <svg
      class="duel-tile-icon duel-icon-sword"
      viewBox="0 0 24 24"
      aria-hidden="true"
      focusable="false"
    >
      <g transform="rotate(45 12 12)">
        <path d="M12 1.5l3.6 3.6V15H8.4V5.1z" />
        <rect x="4.5" y="15.5" width="15" height="3.4" rx="1" />
        <rect x="9.8" y="19" width="4.4" height="3.5" rx="1" />
      </g>
    </svg>
    """
  end

  # The shield before a DEF value
  defp shield_icon(assigns) do
    ~H"""
    <svg
      class="duel-tile-icon duel-icon-shield"
      viewBox="0 0 24 24"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M12 2 4 5v6c0 5 3.4 9.3 8 11 4.6-1.7 8-6 8-11V5z" />
    </svg>
    """
  end

  attr :id, :string, required: true
  attr :seat, :integer, required: true
  attr :player, :map, required: true
  attr :name, :string, required: true
  attr :reveal_all, :boolean, default: false
  attr :on_card, :string, default: nil
  attr :selected, :string, default: nil

  # The field spell zone left of four chips: Deck (a count), Extra, Grave, Banish.
  defp board_stacks(assigns) do
    p = assigns.player

    assigns =
      assigns
      |> assign(:field_card, p["field"])
      |> assign(:deck, p["deck"] || 0)
      |> assign(:chips, [
        {"extra", "Extra", "Extra Deck", p["extra"] || []},
        {"grave", "Grave", "graveyard", p["grave"] || []},
        {"banished", "Banish", "banished cards", p["banished"] || []}
      ])

    ~H"""
    <div class="duel-stackrow">
      <div class="duel-cell duel-cell-field" data-empty={to_string(@field_card == nil)}>
        <span :if={@field_card == nil} class="duel-field-label" aria-hidden="true">Field</span>
        <.tile_button
          :if={@field_card}
          card={@field_card}
          id={@id}
          reveal_all={@reveal_all}
          key={"p#{@seat}:field:0"}
          place={"Player #{@seat} field zone"}
          zone="field"
          player={@seat}
          index={0}
          on_card={@on_card}
          selected={@selected}
        />
      </div>
      <div class="duel-chips">
        <div
          class="duel-chip"
          data-zero={to_string(@deck == 0)}
          id={"#{@id}-chip-#{@seat}-deck"}
          role="group"
          aria-label={"Player #{@seat} Deck, #{count_text(@deck)}"}
        >
          <span aria-hidden="true">Deck</span><b aria-hidden="true">{@deck}</b>
        </div>
        <.chip
          :for={{zone, label, noun, cards} <- @chips}
          id={@id}
          seat={@seat}
          zone={zone}
          label={label}
          noun={noun}
          cards={cards}
        />
      </div>
    </div>
    """
  end

  defp count_text(1), do: "1 card"
  defp count_text(n), do: "#{n} cards"

  attr :id, :string, required: true
  attr :seat, :integer, required: true
  attr :zone, :string, required: true
  attr :label, :string, required: true
  attr :noun, :string, required: true
  attr :cards, :list, required: true

  # A chip: a button that opens the list when it holds cards, a dimmed inert one at 0
  defp chip(assigns) do
    assigns = assign(assigns, :n, length(assigns.cards))

    ~H"""
    <button
      type="button"
      class="duel-chip"
      id={"#{@id}-chip-#{@seat}-#{@zone}"}
      data-zero={to_string(@n == 0)}
      disabled={@n == 0}
      aria-haspopup={@n > 0 && "dialog"}
      aria-label={"Player #{@seat} #{@label}, #{count_text(@n)}"}
      phx-click={@n > 0 && open_sheet("#{@id}-sheet-#{@seat}-#{@zone}")}
    >
      <span aria-hidden="true">{@label}</span><b aria-hidden="true">{@n}</b>
    </button>
    """
  end

  defp open_sheet(sheet) do
    JS.show(to: "##{sheet}", display: "block") |> JS.focus_first(to: "##{sheet}-panel")
  end

  defp close_sheet(sheet, chip) do
    JS.hide(to: "##{sheet}") |> JS.focus(to: "##{chip}")
  end

  attr :id, :string, required: true
  attr :seat, :integer, required: true
  attr :name, :string, required: true
  attr :zone, :string, required: true
  attr :noun, :string, required: true
  attr :cards, :list, required: true
  attr :on_card, :string, default: nil
  attr :selected, :string, default: nil

  # The list a chip opens: a bottom sheet over a dimmed board, mini tiles with names
  defp stack_sheet(assigns) do
    sheet = "#{assigns.id}-sheet-#{assigns.seat}-#{assigns.zone}"
    chip = "#{assigns.id}-chip-#{assigns.seat}-#{assigns.zone}"

    assigns =
      assigns
      |> assign(:sheet, sheet)
      |> assign(:close, close_sheet(sheet, chip))
      |> assign(
        :title,
        "#{assigns.name} · #{String.capitalize(assigns.noun)} (#{length(assigns.cards)})"
      )

    ~H"""
    <div
      id={@sheet}
      class="duel-sheet hidden"
      role="dialog"
      aria-modal="true"
      aria-label={@title}
    >
      <div class="duel-sheet-shade" phx-click={@close}></div>
      <div id={"#{@sheet}-panel"} class="duel-sheet-panel">
        <div class="duel-sheet-head">
          <h3>{@title}</h3>
          <button
            type="button"
            class="duel-board-close"
            phx-click={@close}
            aria-label="Close the list"
            title="Close"
          >
            <.icon name="hero-x-mark" class="size-6" />
          </button>
        </div>
        <ul class="duel-list">
          <li :for={{card, i} <- Enum.with_index(@cards)}>
            <button
              type="button"
              id={"#{@sheet}-card-#{i}"}
              class="duel-list-item"
              data-selected={to_string(@selected == "p#{@seat}:#{@zone}:#{i}")}
              aria-label={list_label(card, "Player #{@seat} #{@noun}")}
              phx-click={@on_card}
              phx-value-key={"p#{@seat}:#{@zone}:#{i}"}
              phx-value-player={@seat}
              phx-value-zone={@zone}
              phx-value-index={i}
            >
              <.tile card={card} variant="list" />
              <span class="duel-list-name" aria-hidden="true">{card["name"]}</span>
              <span :if={monster?(card)} class="duel-list-stats" aria-hidden="true">
                {list_stats(card)}
              </span>
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp list_stats(%{"kind" => "link"} = card), do: "ATK #{stat(card["atk"])}"
  defp list_stats(card), do: "ATK #{stat(card["atk"])} / DEF #{stat(card["def"])}"

  defp list_label(card, place) do
    stats = if monster?(card), do: [String.replace(list_stats(card), " / ", ", ")], else: []
    Enum.join([card["name"]] ++ stats ++ [place], ", ")
  end

  attr :id, :string, required: true
  attr :seat, :integer, required: true
  attr :cards, :list, required: true
  attr :reveal_all, :boolean, default: false
  attr :on_card, :string, default: nil
  attr :selected, :string, default: nil

  # A hand that has cards: a row of small tiles. An empty hand shows nothing.
  defp board_hand(assigns) do
    assigns = assign(assigns, :n, length(assigns.cards))

    ~H"""
    <div
      id={"#{@id}-hand-#{@seat}"}
      class="duel-hand"
      role="group"
      aria-label={"Player #{@seat} hand, #{count_text(@n)}"}
    >
      <p class="duel-hand-label" aria-hidden="true">Hand · {@n}</p>
      <div class="duel-hand-cards">
        <.tile_button
          :for={{card, i} <- Enum.with_index(@cards)}
          card={card}
          id={@id}
          reveal_all={@reveal_all}
          key={"p#{@seat}:hand:#{i}"}
          place={"Player #{@seat} hand, card #{i + 1} of #{@n}"}
          zone="hand"
          player={@seat}
          index={i}
          variant="hand"
          on_card={@on_card}
          selected={@selected}
        />
      </div>
    </div>
    """
  end
end
