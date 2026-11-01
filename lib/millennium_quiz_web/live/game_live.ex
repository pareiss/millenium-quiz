defmodule MillenniumQuizWeb.GameLive do
  @moduledoc """
  Hot-seat game screen. The LiveView never owns game state: it sends intents
  to `MillenniumQuiz.Games` and re-renders whatever the game process
  broadcasts, so a refresh, a second tab or another device all show the same game.
  """
  use MillenniumQuizWeb, :live_view

  import MillenniumQuizWeb.CardComponents

  alias MillenniumQuiz.{Game, Games, GameNotifier, Quiz, RateLimit}
  alias MillenniumQuizWeb.ClientIP
  alias MillenniumQuiz.Quiz.CardLinks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="lg">
      <%!-- keeps the screen awake while the game runs; the banner shows while
           the connection is down (see the phx-offline variant in app.css) --%>
      <div
        id="game-connection"
        phx-hook="WakeLock"
        data-active={to_string(@status == :active and @game.phase != :finished)}
        class="my-0!"
      >
        <p
          id="game-reconnecting"
          role="status"
          aria-live="polite"
          class="mq-offline pointer-events-none fixed inset-x-0 bottom-[calc(1rem+env(safe-area-inset-bottom))] z-50 mx-auto hidden w-fit max-w-[90vw] items-center gap-2 rounded-full border border-base-300 bg-base-100 px-4 py-2 text-sm font-medium shadow-lg phx-offline:flex"
        >
          <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" /> Reconnecting…
        </p>
      </div>
      <div
        id="game"
        phx-hook=".RememberGame"
        data-game-id={@game_id}
        data-finished={to_string(@status == :finished)}
        data-turn-key={turn_key_attr(@turn_key)}
        data-phase={if @status == :paused, do: :paused, else: @game.phase}
        class="space-y-5 transition-opacity phx-offline:pointer-events-none phx-offline:opacity-50 phx-offline:delay-700"
      >
        <.game_header game={@game} status={@status} crops={@crops} />

        <%= cond do %>
          <% @status == :paused -> %>
            <.paused_panel
              game={@game}
              resume_url={@resume_url}
              qr_svg={@qr_svg}
              email_form={@email_form}
            />
          <% @game.phase == :finished -> %>
            <.final_panel game={@game} crops={@crops} />
          <% @game.phase == :choosing -> %>
            <.board_panel game={@game} turn_locked={@turn_locked} />
          <% @game.phase == :answering -> %>
            <.answering_panel game={@game} turn_locked={@turn_locked} crops={@crops} />
          <% @game.phase == :revealed -> %>
            <.reveal_panel game={@game} turn_locked={@turn_locked} crops={@crops} />
        <% end %>

        <.zoomed_card
          :if={@zoom && @status == :active && @game.phase in [:answering, :revealed]}
          game={@game}
          zoom={@zoom}
        />
        <.end_game_modal :if={@confirm_end and @status == :active and @game.phase != :finished} />
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".RememberGame">
        // Remembers unfinished games of this device for the "Continue" list
        // on the home page. Finished games are forgotten again.
        const KEY = "mq:games"
        const read = () => { try { return JSON.parse(localStorage.getItem(KEY) || "[]") } catch (_e) { return [] } }
        export default {
          mounted() { this.turnKey = this.el.dataset.turnKey; this.sync() },
          updated() { this.sync(); this.newTurn() },
          // A new turn (next player, next phase) starts at its panel, not where
          // the last player left the page: the "Pass the device" bar shows.
          // Not while a dialog is open; pauses and re-renders keep the key.
          newTurn() {
            const key = this.el.dataset.turnKey
            if (key === this.turnKey) return
            this.turnKey = key
            if (document.querySelector('[role="dialog"]')) return
            const panel = this.el.querySelector("[data-turn-panel]")
            if (!panel) return
            // only a sticky header covers the top of the page
            const header = document.querySelector("header")
            const sticky = header && getComputedStyle(header).position === "sticky"
            const offset = (sticky ? header.getBoundingClientRect().height : 0) + 12
            const top = Math.max(0, panel.getBoundingClientRect().top + window.scrollY - offset)
            const calm = window.matchMedia("(prefers-reduced-motion: reduce)").matches
            window.scrollTo({top, behavior: calm ? "auto" : "smooth"})
          },
          sync() {
            const id = this.el.dataset.gameId
            let ids = read().filter(x => x !== id)
            if (this.el.dataset.finished !== "true") ids = [id, ...ids].slice(0, 20)
            try { localStorage.setItem(KEY, JSON.stringify(ids)) } catch (_e) {}
          }
        }
      </script>
    </Layouts.app>
    """
  end

  ## Components

  attr :game, Game, required: true
  attr :crops, :map, default: %{}, doc: "slug => crop of the players' card pictures"
  attr :status, :atom, required: true

  defp game_header(assigns) do
    assigns = assign(assigns, :finished?, assigns.game.phase == :finished)

    ~H"""
    <div class="space-y-2 sm:space-y-3">
      <div class="flex flex-wrap items-end justify-between gap-x-3 gap-y-1">
        <div>
          <p class="mq-qhide text-xs sm:text-sm font-medium uppercase tracking-[0.12em] sm:tracking-[0.2em] text-primary">
            {@game.format_name}
            <span class="text-base-content/50" id="game-mode">· {Game.mode_name(@game.mode)}</span>
          </p>
          <%!-- a finished game is no "Question 2 of 20" any more --%>
          <h1
            class="duel-title whitespace-nowrap text-xl sm:text-2xl font-bold tracking-tight"
            id="round-label"
          >
            <%= if @finished? do %>
              Final results
            <% else %>
              Question {@game.round}
              <span class="text-base-content/50">of {Game.total_rounds(@game)}</span>
            <% end %>
          </h1>
        </div>
        <div :if={@status == :active and not @finished?} class="flex shrink-0 gap-2">
          <button class="btn btn-ghost btn-sm" phx-click="pause" id="pause-game">
            <.icon name="hero-pause" class="size-4" /> Pause
          </button>
          <button
            class="btn btn-ghost btn-sm text-error"
            phx-click="confirm_end"
            id="end-game"
          >
            <.icon name="hero-flag" class="size-4" /> End
          </button>
        </div>
      </div>
      <%!-- the final panel has the standings --%>
      <.orb_rail
        :if={not @finished?}
        id="game-progress"
        class="mq-qhide"
        total={Game.total_rounds(@game)}
        current={if @game.phase == :revealed, do: @game.round + 1, else: @game.round}
        label="Question"
      />
      <%!-- while a question is up the css hides it (app.css): a phone or tablet
           needs the room, and the life points are on the board before and in the
           reveal after. A large screen has the room and keeps it. Two to a row on
           a phone (four players too up to lg), so a name keeps its room --%>
      <ul
        :if={not @finished?}
        class="mq-nosel grid grid-cols-2 gap-1.5 sm:gap-2 data-[n='3']:sm:grid-cols-3 data-[n='4']:lg:grid-cols-4"
        id="scoreboard"
        data-n={length(@game.players)}
      >
        <li
          :for={{player, index} <- Enum.with_index(@game.players)}
          id={"score-#{index}"}
          data-eliminated={to_string(not Game.alive?(@game, index))}
          class="min-w-0 max-sm:[&:last-child:nth-child(odd)]:col-span-2"
        >
          <% {status, damage} = gauge_state(@game, index) %>
          <.lp_gauge
            id={"gauge-#{index}"}
            lp_id={"lp-#{index}"}
            bar_id={"lp-bar-#{index}"}
            name={player.name}
            avatar={player.avatar}
            crop={@crops[player.avatar]}
            lp={player.lp}
            start_lp={@game.start_lp}
            player={index}
            status={status}
            damage={damage}
            active={
              @game.phase in [:choosing, :answering] and Game.current_player_index(@game) == index
            }
          />
          <span :if={not Game.alive?(@game, index)} id={"eliminated-#{index}"} class="sr-only">
            Eliminated
          </span>
        </li>
      </ul>
    </div>
    """
  end

  # What a player's gauge shows: in the reveal, the hit of the question just
  # answered (the ghost of the lost life points); otherwise nothing.
  defp gauge_state(%{phase: :revealed} = game, index) do
    question = Game.current_question(game)

    if index in Game.answer_order(game) and not Game.correct?(game, index),
      do: {:hit, min(Game.lp_before_reveal(game, index), question.damage)},
      else: {:alive, nil}
  end

  defp gauge_state(_game, _index), do: {:alive, nil}

  attr :game, Game, required: true
  attr :turn_locked, :boolean, default: false

  defp board_panel(assigns) do
    assigns =
      assigns
      |> assign(:player, Game.current_player(assigns.game))
      |> assign(:board, Game.board(assigns.game))
      |> assign(
        :prompt,
        if(assigns.game.mode == :free, do: "choose a question", else: "choose a topic")
      )

    ~H"""
    <div
      id={"board-panel-#{@game.round}"}
      data-turn-panel
      class="duel-plate duel-panel rounded-box border border-base-300 bg-base-100 shadow-sm overflow-hidden"
    >
      <div class="duel-banner bg-secondary text-secondary-content px-4 py-2.5 sm:px-5 sm:py-3 flex items-center gap-3">
        <.icon name="hero-hand-raised" class="size-5 shrink-0" />
        <p>
          <strong class="text-lg" id="current-player">{@player.name}</strong>, {@prompt}
        </p>
      </div>
      <div class="p-2 sm:p-5 overflow-x-auto">
        <div
          id="board"
          class="mq-board mq-nosel grid gap-x-1.5 gap-y-3 sm:gap-2"
          style={"--cols: #{length(@board)}"}
        >
          <div
            :for={{{topic, cells}, column} <- Enum.with_index(@board)}
            id={"column-#{column}"}
            class="flex flex-col gap-1.5 sm:gap-2"
          >
            <% next = Game.next_in_column(@game, column) %>
            <button
              :if={@game.mode == :ascending and next}
              id={"topic-#{column}"}
              phx-click="choose"
              phx-value-question={next}
              disabled={@turn_locked}
              data-state="next"
              class="duel-plate duel-topic min-h-14 rounded-field bg-primary px-1 py-1 text-xs sm:px-2 sm:text-sm font-semibold text-primary-content shadow-sm transition hover:brightness-110 active:scale-95 phx-click-loading:opacity-50 disabled:opacity-50 disabled:pointer-events-none"
            >
              <span class="line-clamp-3 sm:line-clamp-2 leading-tight hyphens-auto break-words">
                {topic}
              </span>
              <span
                id={"next-atk-#{column}"}
                class="mt-0.5 flex flex-wrap items-baseline justify-center gap-x-1.5 text-[0.65rem] sm:text-xs font-bold uppercase tabular-nums"
              >
                <span class="opacity-80">Next</span>
                <.atk_label value={Game.next_damage(@game, column)} class="text-sm sm:text-base" />
              </span>
            </button>
            <div
              :if={@game.mode == :free or is_nil(next)}
              id={"topic-#{column}"}
              data-state={if next, do: "free", else: "done"}
              class={[
                "duel-plate duel-topic min-h-14 grid place-items-center rounded-field px-1 py-1 text-center text-xs sm:px-2 sm:text-sm font-semibold",
                if(next, do: "bg-base-200", else: "bg-base-200/50 text-base-content/40")
              ]}
            >
              <span class="line-clamp-3 sm:line-clamp-2 leading-tight hyphens-auto break-words">
                {topic}
              </span>
            </div>

            <%= for {index, question} <- cells do %>
              <button
                :if={Game.choosable?(@game, index) and @game.mode == :free}
                id={"question-#{index}"}
                phx-click="choose"
                phx-value-question={index}
                disabled={@turn_locked}
                data-state="open"
                class="duel-plate duel-tile h-14 rounded-field border border-primary/30 bg-primary/10 text-base sm:text-lg font-bold tabular-nums text-base-content transition hover:bg-primary hover:text-primary-content active:scale-95 phx-click-loading:opacity-50 disabled:opacity-50 disabled:pointer-events-none"
              >
                <.atk_label value={question.damage} />
              </button>
              <div
                :if={question.result}
                id={"question-#{index}"}
                data-state="done"
                class="duel-plate duel-tile h-14 flex flex-col items-center justify-center rounded-field bg-base-200/60 px-1 text-xs text-base-content/50"
                title={"#{question.damage} damage"}
              >
                <% correct = Game.correct_count(question) %>
                <span class="flex items-center gap-1 text-sm font-bold tabular-nums">
                  <.icon
                    name={if correct > 0, do: "hero-check", else: "hero-x-mark"}
                    class={["size-4", if(correct > 0, do: "text-success", else: "text-error")]}
                  />
                  {question.damage}
                </span>
                <span class="text-[0.65rem] tabular-nums">
                  {correct}/{Game.answered_count(question)} right
                </span>
              </div>
              <div
                :if={is_nil(question.result) and @game.mode == :ascending}
                id={"question-#{index}"}
                data-state={if index == next, do: "next", else: "later"}
                class={[
                  "duel-plate duel-tile h-14 grid place-items-center rounded-field border text-base sm:text-lg font-bold tabular-nums",
                  if(index == next,
                    do: "border-primary/40 bg-primary/10 text-base-content",
                    else: "border-base-300 text-base-content/40"
                  )
                ]}
              >
                <.atk_label :if={index == next} value={question.damage} />
                <span :if={index != next}>{question.damage}</span>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :game, Game, required: true
  attr :crops, :map, default: %{}, doc: "slug => crop of the players' card pictures"
  attr :turn_locked, :boolean, default: false

  defp answering_panel(assigns) do
    assigns =
      assigns
      |> assign(:question, Game.current_question(assigns.game))
      |> assign(:player, Game.current_player(assigns.game))

    ~H"""
    <div
      id={"turn-#{@game.round}-#{@game.answered}"}
      data-turn-panel
      class="duel-plate duel-panel rounded-box border border-base-300 bg-base-100 shadow-sm overflow-hidden reveal-pop"
    >
      <%!-- goes by itself after about 3 seconds (app.css), when a question comes
           up and again for each next player; on a phone or tablet the choices
           below cannot be tapped until it has gone, so nobody hits the wrong one
           as the page moves, and the line along its bottom runs out meanwhile --%>
      <div class="mq-passbar duel-banner bg-secondary text-secondary-content px-5 py-3 flex items-center gap-3">
        <span class="mq-passbar__timer" aria-hidden="true"></span>
        <.synchro_ring class="size-14 shrink-0">
          <.avatar
            slug={@player.avatar}
            crop={@crops[@player.avatar]}
            title={@player.name}
            class="size-full !ring-0"
          />
        </.synchro_ring>
        <p class="min-w-0">
          Pass the device to <strong class="text-lg" id="current-player">{@player.name}</strong>
        </p>
        <span class="ml-auto text-sm opacity-80" id="answer-progress">
          {@game.answered + 1}/{length(Game.answer_order(@game))}
        </span>
      </div>
      <%!-- one column; question and choices side by side on a wide screen
           (a tablet, a phone on its side) --%>
      <div class="p-3 sm:p-6 grid gap-3 sm:gap-5 md:landscape:grid-cols-2 lg:grid-cols-2 lg:gap-8 items-start">
        <div class="space-y-3 sm:space-y-5">
          <.question_meta question={@question} />
          <p
            class="text-lg sm:text-2xl [@media(max-height:32rem)]:sm:text-lg font-semibold leading-snug"
            id="question-text"
          >
            <.question_text question={@question} />
          </p>
          <.question_link_popovers question={@question} />
          <.question_cards cards={@question.cards} />
        </div>
        <div class="space-y-3 sm:space-y-5">
          <div class="mq-choices grid gap-2 sm:gap-3 sm:grid-cols-2 md:landscape:grid-cols-1 lg:grid-cols-1">
            <button
              :for={{choice, i} <- Enum.with_index(@question.choices)}
              id={"choice-#{i}"}
              phx-click="answer"
              phx-value-choice={i}
              disabled={@turn_locked}
              class="duel-plate duel-choice mq-nosel group flex items-center gap-3 rounded-field border border-base-300 bg-base-100 p-4 text-left transition hover:border-primary hover:bg-primary/5 active:scale-[0.98] phx-click-loading:opacity-50 disabled:opacity-50 disabled:pointer-events-none"
            >
              <span class="duel-letter grid place-items-center size-8 shrink-0 rounded-full bg-base-200 font-semibold group-hover:bg-primary group-hover:text-primary-content transition">
                {<<?A + i>>}
              </span>
              <span><.answer_text text={choice} /></span>
            </button>
          </div>
          <p class="text-sm text-base-content/60">
            Answers stay hidden until everyone has picked.
          </p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  The segments of a question's text: `{:text, binary}` and
  `{:player, 1 | 2}` and `{:card, name, index}`, where `index` is the position in `question.cards`
  (the `phx-value-card` of the `zoom_card` event). Resolved against the
  question as snapshotted in the game, never against the database.
  """
  @spec question_segments(map) :: [CardLinks.segment()]
  def question_segments(%{text: text, cards: cards}), do: CardLinks.parse(text, cards)

  attr :question, :map, required: true

  defp question_text(assigns) do
    assigns = assign(assigns, :segments, numbered_segments(assigns.question))

    ~H"""
    <%= for {seg, n} <- @segments do %>
      <%= case seg do %>
        <% {:text, text} -> %>
          <span>{text}</span>
        <% {:player, player} -> %>
          <.player_badge player={player} />
        <% {:card, name, index} -> %>
          <% owner = card_owner(@question.cards, index) %>
          <button
            type="button"
            id={"question-link-#{n}"}
            phx-click="zoom_card"
            phx-value-card={index}
            data-card-index={index}
            data-owner={owner}
            aria-label={"Show card: #{name}" <> owner_note(owner)}
            title={"Show card: #{name}" <> owner_note(owner)}
            class={[
              "cursor-zoom-in rounded-sm font-semibold underline decoration-dotted decoration-2 underline-offset-4",
              owner == nil &&
                "decoration-[#c39a55] hover:bg-[#c39a55]/20 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#c39a55]",
              owner == 1 &&
                "decoration-[#2563eb] hover:bg-[#2563eb]/15 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#2563eb]",
              owner == 2 &&
                "decoration-[#dc2626] hover:bg-[#dc2626]/15 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#dc2626]"
            ]}
          >
            {name}
          </button>
      <% end %>
    <% end %>
    """
  end

  # The player (1 or 2) a card of the question belongs to, nil for nobody (and
  # for snapshots from before owners).
  defp card_owner(cards, index) do
    case Enum.at(cards, index) do
      %{owner: owner} when owner in [1, 2] -> owner
      _ -> nil
    end
  end

  defp owner_note(nil), do: ""
  defp owner_note(owner), do: " (Player #{owner}'s card)"

  # Segments with a running number for the card links (their DOM ids).
  defp numbered_segments(question) do
    {segments, _} =
      question
      |> question_segments()
      |> Enum.map_reduce(0, fn
        {:card, _, _} = seg, n -> {{seg, n}, n + 1}
        seg, n -> {{seg, nil}, n}
      end)

    segments
  end

  attr :question, :map, required: true

  # The drawn cards that hovering or focusing a link in the question text
  # shows: one per distinct linked card, hidden (so artwork is not loaded)
  # until the hook places it next to the link. Kept outside the text, as a
  # card is made of blocks. Decorative for assistive technology: the link's
  # own label names the card. No popover on devices without hover.
  defp question_link_popovers(assigns) do
    indexes =
      assigns.question
      |> question_segments()
      |> Enum.flat_map(fn
        {:card, _name, index} -> [index]
        _ -> []
      end)
      |> Enum.uniq()

    assigns = assign(assigns, :indexes, indexes)

    ~H"""
    <div
      :if={@indexes != []}
      id="question-link-popovers"
      aria-hidden="true"
      phx-hook=".CardLinkPopover"
    >
      <div
        :for={i <- @indexes}
        id={"question-link-popover-#{i}"}
        class="mq-linkpop w-44"
        data-card-index={i}
      >
        <.card card={Enum.at(@question.cards, i)} />
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CardLinkPopover">
        export default {
          mounted() {
            this.open = null
            this.hide = () => {
              if (this.open) delete this.open.dataset.open
              this.open = null
            }
            this.show = (event) => {
              if (!window.matchMedia("(hover: hover)").matches) return
              const link = event.target.closest && event.target.closest("#question-text [data-card-index]")
              if (!link) return
              const pop = this.el.querySelector(`[data-card-index="${link.dataset.cardIndex}"]`)
              if (!pop) return
              this.hide()
              pop.dataset.open = ""
              const anchor = link.getBoundingClientRect()
              const box = pop.getBoundingClientRect()
              const margin = 8
              const left = Math.max(margin, Math.min(anchor.left + anchor.width / 2 - box.width / 2, window.innerWidth - box.width - margin))
              const above = anchor.top - box.height - margin
              const top = above >= margin ? above : Math.min(anchor.bottom + margin, Math.max(margin, window.innerHeight - box.height - margin))
              pop.style.left = `${left}px`
              pop.style.top = `${top}px`
              this.open = pop
            }
            this.onKey = (event) => { if (event.key === "Escape") this.hide() }
            this.hideOut = (event) => {
              if (event.target.closest && event.target.closest("#question-text [data-card-index]")) this.hide()
            }
            document.addEventListener("mouseover", this.show)
            document.addEventListener("focusin", this.show)
            document.addEventListener("mouseout", this.hideOut)
            document.addEventListener("focusout", this.hideOut)
            document.addEventListener("keydown", this.onKey)
            window.addEventListener("scroll", this.hide, true)
            document.addEventListener("click", this.hide)
          },
          destroyed() {
            document.removeEventListener("mouseover", this.show)
            document.removeEventListener("focusin", this.show)
            document.removeEventListener("mouseout", this.hideOut)
            document.removeEventListener("focusout", this.hideOut)
            document.removeEventListener("keydown", this.onKey)
            window.removeEventListener("scroll", this.hide, true)
            document.removeEventListener("click", this.hide)
          }
        }
      </script>
    </div>
    """
  end

  attr :id, :string, required: true
  slot :inner_block, required: true

  # The call to action at the foot of a panel: when the panel is taller than
  # the screen, the bar stays at the bottom edge (above the home indicator)
  # instead of waiting below the fold. The negative margins run it to the
  # panel's edges.
  defp sticky_bar(assigns) do
    ~H"""
    <div
      id={@id}
      class="duel-foot sticky bottom-0 z-10 -mx-4 -mb-4 rounded-b-box border-t border-base-300 bg-base-100 px-4 pt-3 pb-[calc(0.75rem+env(safe-area-inset-bottom))] [@media(max-height:32rem)]:pt-1.5 [@media(max-height:32rem)]:pb-[calc(0.375rem+env(safe-area-inset-bottom))] sm:-mx-6 sm:-mb-6 sm:px-6"
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :game, Game, required: true
  attr :crops, :map, default: %{}, doc: "slug => crop of the players' card pictures"
  attr :turn_locked, :boolean, default: false

  defp reveal_panel(assigns) do
    question = Game.current_question(assigns.game)

    assigns =
      assigns
      |> assign(:question, question)
      |> assign(:chooser, Enum.at(assigns.game.players, question.result.chooser))
      |> assign(:last_round?, Game.over?(assigns.game))
      |> assign(:headline, reveal_headline(assigns.game))

    ~H"""
    <div
      class="duel-plate duel-panel rounded-box border border-base-300 bg-base-100 shadow-sm p-4 sm:p-6 space-y-5 reveal-pop"
      id="reveal"
    >
      <h2 id="reveal-headline" class="duel-headline" data-tone={elem(@headline, 0)}>
        {elem(@headline, 1)}
      </h2>
      <div class="grid gap-5 md:landscape:grid-cols-2 lg:grid-cols-2 lg:gap-8 items-start">
        <div class="space-y-5">
          <.question_meta question={@question} />
          <p class="text-xl font-semibold leading-snug" id="question-text">
            <.question_text question={@question} />
          </p>
          <.question_link_popovers question={@question} />
          <.question_cards cards={@question.cards} />
          <p class="flex items-center gap-2 text-sm text-base-content/60">
            Chosen by <.avatar slug={@chooser.avatar} crop={@crops[@chooser.avatar]} class="size-9" />
            <span>{@chooser.name}</span>
          </p>
          <p
            :if={@question[:submitted_by]}
            class="flex items-center gap-2 text-sm text-base-content/60"
            id="submitted-by"
          >
            <.icon name="hero-light-bulb" class="size-5 text-primary" />
            <span>Question suggested by {@question[:submitted_by]}</span>
          </p>
        </div>

        <div class="space-y-5">
          <ul class="grid gap-2 sm:grid-cols-2 md:landscape:grid-cols-1 lg:grid-cols-1">
            <li
              :for={{choice, i} <- Enum.with_index(@question.choices)}
              id={"reveal-choice-#{i}"}
              data-correct={to_string(i == @question.correct)}
              class={[
                "duel-plate duel-choice flex items-center gap-3 rounded-field border p-3",
                if(i == @question.correct,
                  do: "border-success bg-success/15 font-semibold",
                  else: "border-base-300 opacity-60"
                )
              ]}
            >
              <span class="grid place-items-center size-7 shrink-0 rounded-full bg-base-200 text-sm">
                {<<?A + i>>}
              </span>
              <span class="flex-1"><.answer_text text={choice} /></span>
              <.icon
                :if={i == @question.correct}
                name="hero-check-circle"
                class="size-6 text-success"
              />
            </li>
          </ul>

          <p
            :if={Game.correct_count(@question) == 0}
            id="all-wrong"
            class="text-sm font-semibold text-error"
          >
            Nobody was right: everyone takes {@question.damage} damage.
          </p>
          <ul
            class="duel-rows divide-y divide-base-300 rounded-field border border-base-300"
            id="round-results"
          >
            <li
              :for={index <- Game.answer_order(@game)}
              id={"result-#{index}"}
              data-result={result_kind(@game, index)}
              class="duel-plate duel-row flex flex-wrap items-center gap-x-2 gap-y-1 px-3 py-2.5 sm:gap-x-3 sm:px-4"
            >
              <% correct? = Game.correct?(@game, index) %>
              <% player = Enum.at(@game.players, index) %>
              <.icon
                name={if correct?, do: "hero-check-circle", else: "hero-x-circle"}
                class={["size-5 shrink-0", if(correct?, do: "text-success", else: "text-error")]}
              />
              <.avatar
                slug={player.avatar}
                crop={@crops[player.avatar]}
                class="size-12"
              />
              <span class="min-w-0 font-medium break-words">{player.name}</span>
              <span class="shrink-0 text-sm text-base-content/60">
                picked {<<?A + Enum.at(@question.result.picks, index)>>}
              </span>
              <span class={[
                "ml-auto tabular-nums font-semibold",
                if(correct?, do: "text-success", else: "text-base-content/40")
              ]}>
                {if correct?,
                  do: "0",
                  else: "-#{min(Game.lp_before_reveal(@game, index), @question.damage)}"}
              </span>
              <p
                :if={correct?}
                id={"damage-result-#{index}"}
                class="duel-eq basis-full text-sm text-base-content/60 tabular-nums"
              >
                No damage. <span class="font-semibold">{player.lp} LP</span>
              </p>
              <p
                :if={not correct? and Game.alive?(@game, index)}
                id={"damage-result-#{index}"}
                class="duel-eq basis-full text-sm font-semibold text-error tabular-nums"
              >
                Direct hit! <span class="duel-eq-lp">{player.lp + @question.damage}</span>
                - <span class="duel-eq-dmg">{@question.damage}</span>
                = <span class="duel-eq-lp">{player.lp}</span>
                LP
              </p>
              <p
                :if={not correct? and not Game.alive?(@game, index)}
                id={"damage-result-#{index}"}
                class="duel-eq basis-full text-sm font-bold text-error tabular-nums"
              >
                K.O.! <span class="duel-eq-lp">{Game.lp_before_reveal(@game, index)}</span>
                LP, <span class="duel-eq-dmg">{@question.damage}</span>
                damage: 0 LP left.
                <span id={"ko-#{index}"} class="duel-ko-tag uppercase">Eliminated</span>
              </p>
            </li>
          </ul>
        </div>
      </div>

      <.sticky_bar id="reveal-bar">
        <button
          class="btn btn-primary btn-block btn-lg"
          phx-click="next_round"
          id="next-round"
          disabled={@turn_locked}
        >
          {if @last_round?, do: "Show final results", else: "Back to the board"}
          <.icon name="hero-arrow-right" class="size-5" />
        </button>
      </.sticky_bar>
    </div>
    """
  end

  # The headline of a reveal: a knock-out, a hit or no damage at all.
  defp reveal_headline(game) do
    wrong = Enum.reject(Game.answer_order(game), &Game.correct?(game, &1))

    cond do
      Enum.any?(wrong, &(not Game.alive?(game, &1))) -> {"ko", "K.O.!"}
      wrong != [] -> {"hit", "Damage!"}
      true -> {"safe", "No damage!"}
    end
  end

  defp result_kind(game, index) do
    cond do
      Game.correct?(game, index) -> "right"
      Game.alive?(game, index) -> "hit"
      true -> "ko"
    end
  end

  attr :cards, :list, required: true

  # The cards a question is about, drawn with their text as of the format's
  # date. A tap enlarges a card; a tap on a long text shows it in a panel.
  defp question_cards(assigns) do
    ~H"""
    <div :if={@cards != []} class="space-y-2">
      <p class="text-sm text-base-content/60" id="question-cards-hint">
        <span class="[@media(hover:hover)]:hidden">Tap a card to enlarge it.</span>
        <span class="hidden [@media(hover:hover)]:inline">Click a card to enlarge it.</span>
      </p>
      <%!-- Below sm (a phone upright): two to a row, whatever the width. From sm
           up a card is a quarter of the row, between 8.5 and 11 rem wide: 4 fit
           a portrait tablet (a row of about 670 to 740 px), 3 the half column of
           a landscape one, 2 a phone on its side; a short screen (under 32rem high) lets
           a card shrink to 6.5rem, so 4 fit there too --%>
      <div class="flex flex-wrap gap-3" id="question-cards">
        <article
          :for={{card, i} <- Enum.with_index(@cards)}
          id={"question-card-#{i}"}
          class="w-[calc(50%-0.375rem)] sm:w-[clamp(8.5rem,calc((100%_-_2.25rem)/4),11rem)] [@media(min-width:40rem)_and_(max-height:32rem)]:w-[clamp(6.5rem,calc((100%_-_2.25rem)/4),11rem)]"
        >
          <div
            class="mq-nosel mq-owned relative cursor-zoom-in transition motion-safe:hover:-translate-y-1 hover:drop-shadow-lg"
            data-owner={card_owner(@cards, i)}
            phx-click="zoom_card"
            phx-value-card={i}
          >
            <.player_badge
              :if={card_owner(@cards, i)}
              player={card_owner(@cards, i)}
              class="mq-owner-badge absolute -top-3 left-2 z-10 !mx-0 shadow"
            />
            <.card card={card} on_text="read_card" text_value={i} />
            <%!-- For keyboards; mice can click anywhere on the card --%>
            <button
              type="button"
              phx-click="zoom_card"
              phx-value-card={i}
              id={"zoom-card-#{i}"}
              class="sr-only focus-visible:not-sr-only focus-visible:absolute focus-visible:inset-x-2 focus-visible:top-1/3 focus-visible:rounded-field focus-visible:bg-primary focus-visible:px-2 focus-visible:py-1.5 focus-visible:text-sm focus-visible:font-semibold focus-visible:text-primary-content focus-visible:shadow-lg"
            >
              Enlarge {card.name}
            </button>
          </div>
          <p :if={card.set} class="mt-1.5 text-center text-xs text-base-content/60">
            As printed in {card.set}
          </p>
        </article>
      </div>
    </div>
    <.card_credit :if={@cards != []} />
    """
  end

  attr :game, Game, required: true
  attr :zoom, :any, required: true, doc: "`{:card | :text, index}`"

  defp zoomed_card(assigns) do
    {view, index} = assigns.zoom
    question = Game.current_question(assigns.game)

    assigns =
      assign(assigns,
        view: view,
        index: index,
        card: question && Enum.at(question.cards, index),
        names: if(question, do: Enum.map(question.cards, & &1.name), else: [])
      )

    ~H"""
    <.card_dialog
      :if={@card && @view == :card}
      id="card-zoom"
      card={@card}
      on_close="close_card"
      on_text="read_card"
      text_value={@index}
      count={length(@names)}
      index={@index}
      on_cycle="cycle_card"
      names={@names}
    >
      <.card_credit class="text-center text-white/70" />
      <p class="mq-stage__hint text-xs text-white/70 text-center" id="card-zoom-hint">
        <span class="[@media(hover:hover)]:hidden">Tap outside the card to close.</span>
        <span class="hidden [@media(hover:hover)]:inline">
          Click outside the card or press Esc to close.
        </span>
      </p>
    </.card_dialog>
    <.card_text_dialog
      :if={@card && @view == :text}
      id="card-text"
      card={@card}
      on_close="close_card"
      on_back="zoom_card"
      back_value={@index}
      count={length(@names)}
      index={@index}
      on_cycle="cycle_card"
      names={@names}
    >
      <.card_credit class="text-center text-white/70" />
    </.card_text_dialog>
    """
  end

  attr :class, :any, default: "text-base-content/50"

  # Yugipedia's texts are CC BY-SA: credited wherever card texts are shown.
  defp card_credit(assigns) do
    ~H"""
    <p class={["text-xs", @class]}>
      Card texts from
      <a
        href="https://yugipedia.com"
        target="_blank"
        rel="noopener"
        class="link pointer-coarse:-my-3.5 pointer-coarse:inline-block pointer-coarse:py-3.5"
      >Yugipedia</a>
      (CC BY-SA 4.0) and <a
        href="https://github.com/DawnbrandBots/yaml-yugi"
        target="_blank"
        rel="noopener"
        class="link pointer-coarse:-my-3.5 pointer-coarse:inline-block pointer-coarse:py-3.5"
      >YAML Yugi</a>.
      Yu-Gi-Oh! card names and texts © Konami.
    </p>
    """
  end

  attr :question, :map, required: true

  defp question_meta(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2 text-sm">
      <span class="duel-tag badge badge-outline">{@question.topic}</span>
      <span class="duel-tag duel-tag--atk badge badge-primary" id="question-points">
        {@question.damage} ATK
      </span>
    </div>
    """
  end

  defp end_game_modal(assigns) do
    ~H"""
    <.confirm_dialog
      id="end-game-modal"
      title="End the game?"
      icon="hero-flag"
      on_cancel="cancel_end"
      cancel_id="cancel-end"
    >
      <p>
        The final results are shown right away, ranked by life points. A question that is not revealed yet costs nobody life points.
      </p>
      <p class="mt-2 text-sm text-base-content/60">
        Just need a break? Pause instead and continue later.
      </p>
      <:actions>
        <button class="btn btn-ghost" phx-click="cancel_end" id="cancel-end">Keep playing</button>
        <button class="btn" phx-click="pause" id="pause-instead">
          <.icon name="hero-pause" class="size-4" /> Pause
        </button>
        <button class="btn btn-error" phx-click="finish" id="confirm-end">
          <.icon name="hero-flag" class="size-4" /> End game
        </button>
      </:actions>
    </.confirm_dialog>
    """
  end

  attr :game, Game, required: true
  attr :resume_url, :string, required: true
  attr :qr_svg, :string, required: true
  attr :email_form, :any, required: true

  defp paused_panel(assigns) do
    ~H"""
    <div
      class="duel-plate duel-panel mx-auto max-w-2xl rounded-box border border-primary/50 bg-base-100 shadow-sm p-5 sm:p-6 space-y-6"
      id="paused"
    >
      <div class="flex items-start gap-3">
        <span class="grid place-items-center size-10 rounded-full bg-primary text-primary-content">
          <.icon name="hero-pause" class="size-5" />
        </span>
        <div>
          <h2 class="text-xl font-semibold">Game paused</h2>
          <p class="text-base-content/70">
            The game is saved on the server. Continue here later, or on any other device with the link below.
          </p>
        </div>
      </div>

      <div class="grid gap-6 sm:grid-cols-[1fr_auto] items-start">
        <div class="space-y-5">
          <div class="space-y-2">
            <p class="font-medium">Resume link</p>
            <div class="join w-full">
              <input
                id="resume-url"
                type="text"
                readonly
                value={@resume_url}
                class="input join-item w-full font-mono text-sm"
              />
              <button
                id="copy-resume-url"
                class="btn join-item"
                phx-hook=".CopyLink"
                data-target="resume-url"
                type="button"
              >
                <.icon name="hero-clipboard-document" class="size-4" />
                <span data-label>Copy</span>
              </button>
            </div>
          </div>

          <.form
            for={@email_form}
            id="email-form"
            phx-submit="send_email"
            class="space-y-2"
          >
            <p class="font-medium">Email the link</p>
            <div class="flex gap-2 items-start">
              <div class="flex-1">
                <.input
                  field={@email_form[:email]}
                  type="email"
                  placeholder="you@example.com"
                  required
                />
              </div>
              <button type="submit" class="btn" phx-disable-with="Sending…">
                <.icon name="hero-envelope" class="size-4" /> Send
              </button>
            </div>
            <p class="text-xs text-base-content/60">The address is only used for this one email.</p>
          </.form>
        </div>

        <figure class="text-center space-y-2">
          <div class="rounded-field bg-white p-2 inline-block" id="resume-qr">
            {raw(@qr_svg)}
          </div>
          <figcaption class="text-xs text-base-content/60">Scan to continue on a phone</figcaption>
        </figure>
      </div>

      <button class="btn btn-primary btn-block" phx-click="resume" id="resume-game">
        <.icon name="hero-play" class="size-5" /> Resume on this device
      </button>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyLink">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              const input = document.getElementById(this.el.dataset.target)
              const label = this.el.querySelector("[data-label]")
              const done = () => { label.textContent = "Copied!"; setTimeout(() => label.textContent = "Copy", 1500) }
              if (navigator.clipboard) {
                navigator.clipboard.writeText(input.value).then(done)
              } else {
                input.select(); document.execCommand("copy"); done()
              }
            })
          }
        }
      </script>
    </div>
    """
  end

  attr :game, Game, required: true
  attr :crops, :map, default: %{}, doc: "slug => crop of the players' card pictures"

  defp final_panel(assigns) do
    standings = Game.places(assigns.game)
    winners = for {p, _} <- Game.winners(assigns.game), do: p.name

    assigns =
      assigns
      |> assign(:standings, standings)
      |> assign(:draw?, Game.draw?(assigns.game))
      |> assign(:winners, winners)

    ~H"""
    <div
      class="duel-plate duel-panel mx-auto max-w-2xl rounded-box border border-primary/50 bg-base-100 shadow-sm p-4 sm:p-6 space-y-6 text-center"
      id="final"
    >
      <div class="space-y-2">
        <%!-- the ranking of a duel; a game from before the life points has none --%>
        <p
          :if={@game.start_lp}
          id="final-headline"
          class="duel-headline"
          data-tone={if @draw?, do: "hit", else: "duel"}
        >
          {if @draw?, do: "Draw!", else: "Duel over"}
        </p>
        <span class="duel-trophy inline-grid place-items-center size-16 rounded-full bg-primary text-primary-content shadow">
          <.icon name="hero-trophy" class="size-8" />
        </span>
        <h2 class="text-3xl font-bold" id="winner">
          {cond do
            length(@winners) == 1 -> "#{hd(@winners)} wins!"
            @draw? -> "Draw: #{Enum.join(@winners, " & ")}"
            true -> "Tie: #{Enum.join(@winners, " & ")}"
          end}
        </h2>
      </div>

      <ol class="space-y-2 text-left max-w-sm mx-auto" id="final-standings">
        <li
          :for={{player, index, rank} <- @standings}
          id={"final-player-#{index}"}
          data-rank={rank}
          data-player={index + 1}
          class={[
            "duel-plate duel-rank flex items-center gap-2 rounded-field border px-3 py-3 sm:gap-3 sm:px-4",
            if(rank == 1, do: "border-primary bg-primary/10", else: "border-base-300")
          ]}
        >
          <span class="duel-rank-no w-5 shrink-0 text-base-content/60 tabular-nums sm:w-6">{rank}.</span>
          <.avatar
            slug={player.avatar}
            crop={@crops[player.avatar]}
            class="size-10 shrink-0 sm:size-16"
          />
          <span class="min-w-[3.5rem] flex-1">
            <span class="block font-medium break-words">{player.name}</span>
            <span
              :if={player.lp && Game.alive?(@game, index)}
              class="duel-rank-bar mt-1"
              aria-hidden="true"
            >
              <span style={"width:#{lp_percent(player.lp, @game.start_lp)}%"}></span>
            </span>
          </span>
          <span
            :if={Game.alive?(@game, index)}
            id={"final-lp-#{index}"}
            class="duel-rank-lp shrink-0 text-sm font-semibold tabular-nums sm:text-base"
          >
            {player.lp || player.score}{if player.lp, do: " LP"}
          </span>
          <span
            :if={not Game.alive?(@game, index)}
            id={"final-eliminated-#{index}"}
            class="text-sm font-bold uppercase tracking-wide text-error"
          >
            Eliminated
          </span>
        </li>
      </ol>

      <.sticky_bar id="final-bar">
        <div class="flex flex-wrap justify-center gap-2">
          <.link
            navigate={~p"/formats/#{@game.format_id}/play?#{play_again_params(@game)}"}
            class="btn btn-primary"
            id="play-again"
          >
            <.icon name="hero-arrow-path" class="size-5" /> Play again
          </.link>
          <.link navigate={~p"/"} class="btn btn-ghost">Other formats</.link>
        </div>
      </.sticky_bar>
    </div>
    """
  end

  # Share of the starting life points left, 0 to 100.
  defp lp_percent(lp, start_lp) when is_integer(lp) and is_integer(start_lp) and start_lp > 0,
    do: lp |> Kernel.*(100) |> div(start_lp) |> min(100) |> max(0)

  defp lp_percent(_lp, _start_lp), do: 0

  # The names, mode and life points of a finished game, for "Play again".
  defp play_again_params(game) do
    [players: Enum.map(game.players, & &1.name), mode: game.mode] ++
      if(game.start_lp, do: [start_lp: game.start_lp], else: [])
  end

  ## Lifecycle

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Games.fetch_game(id) do
      {:ok, view} ->
        if connected?(socket), do: Games.subscribe(view.id)

        {:ok,
         socket
         |> assign(:game_id, view.id)
         # connect_info is only readable in mount.
         |> assign(:client_ip, ClientIP.from_socket(socket))
         |> assign(:resume_url, url(~p"/games/#{view.id}"))
         |> assign(:qr_svg, nil)
         |> assign(:confirm_end, false)
         |> assign(:turn_key, nil)
         |> assign(:turn_locked, false)
         |> assign(:email_form, to_form(%{"email" => ""}, as: :resume))
         # The players' pictures never change during a game: one query here.
         |> assign(
           :crops,
           Quiz.avatar_crops(Enum.map(view.game.players, & &1.avatar), defaults: true)
         )
         |> assign_view(view)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "That game does not exist.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:game_updated, view}, socket), do: {:noreply, assign_view(socket, view)}

  def handle_info({:unlock_turn, key}, %{assigns: %{turn_key: key}} = socket),
    do: {:noreply, assign(socket, :turn_locked, false)}

  # A timer of an earlier turn: the current turn stays locked.
  def handle_info({:unlock_turn, _key}, socket), do: {:noreply, socket}

  @impl true
  # Right after a turn starts, taps that advance it are ignored: a double tap
  # or a hand-over tap must not act for the next player.
  def handle_event(event, _params, %{assigns: %{turn_locked: true}} = socket)
      when event in ["answer", "choose", "next_round"],
      do: {:noreply, socket}

  def handle_event("answer", %{"choice" => choice}, socket) do
    case parse_index(choice) do
      {:ok, choice} -> run(socket, &Games.answer(&1, choice))
      :error -> {:noreply, socket}
    end
  end

  def handle_event("choose", %{"question" => index}, socket) do
    case parse_index(index) do
      {:ok, index} -> run(socket, &Games.choose(&1, index))
      :error -> {:noreply, socket}
    end
  end

  def handle_event("next_round", _params, socket), do: run(socket, &Games.next_round/1)

  def handle_event("zoom_card", %{"card" => index}, socket), do: zoom(socket, :card, index)
  def handle_event("read_card", %{"card" => index}, socket), do: zoom(socket, :text, index)

  def handle_event("cycle_card", %{"dir" => dir}, socket) when dir in ["next", "prev"],
    do: cycle_card(socket, if(dir == "next", do: 1, else: -1))

  def handle_event("cycle_card", _params, socket), do: {:noreply, socket}

  def handle_event("close_card", _params, socket), do: {:noreply, assign(socket, :zoom, nil)}

  def handle_event("confirm_end", _params, socket),
    do: {:noreply, assign(socket, :confirm_end, true)}

  def handle_event("cancel_end", _params, socket),
    do: {:noreply, assign(socket, :confirm_end, false)}

  def handle_event("finish", _params, socket),
    do: socket |> assign(:confirm_end, false) |> run(&Games.finish/1)

  def handle_event("pause", _params, socket),
    do: socket |> assign(:confirm_end, false) |> run(&Games.pause/1)

  def handle_event("resume", _params, socket), do: run(socket, &Games.resume/1)

  def handle_event("send_email", %{"resume" => %{"email" => email}}, socket)
      when is_binary(email) do
    email = String.trim(email)

    if email =~ ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/ and String.length(email) <= 160 do
      limits = [
        email_game: socket.assigns.game_id,
        email_ip: socket.assigns.client_ip,
        email_global: :all
      ]

      with :ok <- RateLimit.check_all(limits),
           {:ok, _} <-
             GameNotifier.deliver_resume_link(
               email,
               socket.assigns.resume_url,
               socket.assigns.game
             ) do
        {:noreply,
         socket
         |> put_flash(:info, "Resume link sent to #{email}.")
         |> assign(:email_form, to_form(%{"email" => ""}, as: :resume))}
      else
        {:error, retry_after_ms} when is_integer(retry_after_ms) ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Too many emails sent. Please try again in #{RateLimit.describe_wait(retry_after_ms)}."
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "The email could not be sent.")}
      end
    else
      form =
        to_form(%{"email" => email}, as: :resume, errors: [email: {"is not a valid email", []}])

      {:noreply, assign(socket, :email_form, form)}
    end
  end

  # Only cards of the current question can be enlarged.
  defp zoom(socket, view, index) do
    question = Game.current_question(socket.assigns.game)
    cards = if question, do: length(question.cards), else: 0

    case parse_index(index) do
      {:ok, index} when index < cards -> {:noreply, assign(socket, :zoom, {view, index})}
      _ -> {:noreply, socket}
    end
  end

  # Steps through the cards of the current question, keeping the open view.
  defp cycle_card(socket, step) do
    question = Game.current_question(socket.assigns.game)
    cards = if question, do: length(question.cards), else: 0

    case socket.assigns.zoom do
      {view, index} when cards > 1 and index < cards ->
        {:noreply, assign(socket, :zoom, {view, Integer.mod(index + step, cards)})}

      _ ->
        {:noreply, socket}
    end
  end

  # Event values come from the client: only a non-negative integer as a
  # string is an index; anything else (another type, garbage) is ignored.
  defp parse_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {index, ""} when index >= 0 -> {:ok, index}
      _ -> :error
    end
  end

  defp parse_index(_value), do: :error

  defp run(socket, fun) do
    case fun.(socket.assigns.game_id) do
      {:ok, view} ->
        {:noreply, assign_view(socket, view)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "That action is not possible right now.")}
    end
  end

  # Any change to the game closes an enlarged card: it belongs to a moment
  # (the next player shouldn't find it open).
  defp assign_view(socket, view) do
    socket
    |> assign(:zoom, nil)
    |> assign(:status, view.status)
    |> assign(:game, view.game)
    |> lock_new_turn(view.game)
    |> assign(:page_title, page_title(view.game))
    |> maybe_assign_qr()
  end

  defp page_title(%{phase: :finished} = game), do: "#{game.format_name} · Final results"
  defp page_title(game), do: "#{game.format_name} · Q#{game.round}"

  # A turn is a phase of a round, and each player's answer is one. The first
  # view after mounting never locks (a resumed game must be usable at once);
  # a later change of turn locks for `:turn_lock_ms` (0 disables the lock).
  defp lock_new_turn(socket, game) do
    key = {game.round, game.phase, game.answered}
    delay = Application.get_env(:millennium_quiz, :turn_lock_ms, 700)

    cond do
      key == socket.assigns.turn_key ->
        socket

      is_nil(socket.assigns.turn_key) or delay <= 0 or game.phase == :finished ->
        socket |> assign(:turn_key, key) |> assign(:turn_locked, false)

      true ->
        Process.send_after(self(), {:unlock_turn, key}, delay)
        socket |> assign(:turn_key, key) |> assign(:turn_locked, true)
    end
  end

  defp turn_key_attr(nil), do: nil
  defp turn_key_attr({round, phase, answered}), do: "#{round}-#{phase}-#{answered}"

  # The QR code is only rendered (and computed) while paused.
  defp maybe_assign_qr(%{assigns: %{status: :paused, qr_svg: nil}} = socket) do
    svg = socket.assigns.resume_url |> EQRCode.encode() |> EQRCode.svg(width: 168)
    assign(socket, :qr_svg, svg)
  end

  defp maybe_assign_qr(socket), do: socket
end
