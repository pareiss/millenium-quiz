defmodule MillenniumQuizWeb.GameLive do
  @moduledoc """
  Hot-seat game screen. The LiveView never owns game state: it sends intents
  to `MillenniumQuiz.Games` and re-renders whatever the game process
  broadcasts, so a refresh, a second tab or another device all show the same game.
  """
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.{Game, Games, GameNotifier}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="game"
        phx-hook=".RememberGame"
        data-game-id={@game_id}
        data-finished={to_string(@status == :finished)}
        class="space-y-5"
      >
        <.game_header game={@game} status={@status} />

        <%= cond do %>
          <% @status == :paused -> %>
            <.paused_panel
              game={@game}
              resume_url={@resume_url}
              qr_svg={@qr_svg}
              email_form={@email_form}
            />
          <% @game.phase == :finished -> %>
            <.final_panel game={@game} />
          <% @game.phase == :choosing -> %>
            <.board_panel game={@game} />
          <% @game.phase == :answering -> %>
            <.answering_panel game={@game} />
          <% @game.phase == :revealed -> %>
            <.reveal_panel game={@game} />
        <% end %>

        <.end_game_modal :if={@confirm_end and @status == :active and @game.phase != :finished} />
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".RememberGame">
        // Remembers unfinished games of this device for the "Continue" list
        // on the home page. Finished games are forgotten again.
        const KEY = "mq:games"
        const read = () => { try { return JSON.parse(localStorage.getItem(KEY) || "[]") } catch (_e) { return [] } }
        export default {
          mounted() { this.sync() },
          updated() { this.sync() },
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
  attr :status, :atom, required: true

  defp game_header(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="flex items-end justify-between gap-4">
        <div>
          <p class="text-sm font-medium uppercase tracking-[0.2em] text-primary">
            {@game.category_name}
            <span class="text-base-content/50" id="game-mode">· {Game.mode_name(@game.mode)}</span>
          </p>
          <h1 class="text-2xl font-bold tracking-tight" id="round-label">
            Question {@game.round}
            <span class="text-base-content/50">of {Game.total_rounds(@game)}</span>
          </h1>
        </div>
        <div :if={@status == :active and @game.phase != :finished} class="flex gap-1">
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
      <progress
        class="progress progress-primary w-full"
        value={Enum.count(@game.questions, & &1.result)}
        max={Game.total_rounds(@game)}
      />
      <ul class="grid grid-cols-2 sm:grid-cols-4 gap-2" id="scoreboard">
        <li
          :for={{player, index} <- Enum.with_index(@game.players)}
          id={"score-#{index}"}
          class={[
            "rounded-field border px-3 py-2 transition",
            if(Game.current_player_index(@game) == index,
              do: "border-primary bg-primary/10 shadow-sm",
              else: "border-base-300 bg-base-100"
            )
          ]}
        >
          <p class="text-sm truncate">{player.name}</p>
          <p class="text-lg font-semibold tabular-nums">{player.score}</p>
        </li>
      </ul>
    </div>
    """
  end

  attr :game, Game, required: true

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
      class="rounded-box border border-base-300 bg-base-100 shadow-sm overflow-hidden"
    >
      <div class="bg-secondary text-secondary-content px-5 py-3 flex items-center gap-3">
        <.icon name="hero-hand-raised" class="size-5" />
        <p>
          <strong class="text-lg" id="current-player">{@player.name}</strong>, {@prompt}
        </p>
      </div>
      <div class="p-3 sm:p-5 overflow-x-auto">
        <div
          id="board"
          class="grid gap-2"
          style={"grid-template-columns: repeat(#{length(@board)}, minmax(4.5rem, 1fr))"}
        >
          <div
            :for={{{topic, cells}, column} <- Enum.with_index(@board)}
            id={"column-#{column}"}
            class="flex flex-col gap-2"
          >
            <% next = Game.next_in_column(@game, column) %>
            <button
              :if={@game.mode == :ascending and next}
              id={"topic-#{column}"}
              phx-click="choose"
              phx-value-question={next}
              class="min-h-14 rounded-field bg-primary px-2 py-1 text-sm font-semibold text-primary-content shadow-sm transition hover:brightness-110 active:scale-95 phx-click-loading:opacity-50"
            >
              <span class="line-clamp-2">{topic}</span>
            </button>
            <div
              :if={@game.mode == :free or is_nil(next)}
              id={"topic-#{column}"}
              class={[
                "min-h-14 grid place-items-center rounded-field px-2 py-1 text-center text-sm font-semibold",
                if(next, do: "bg-base-200", else: "bg-base-200/50 text-base-content/40")
              ]}
            >
              <span class="line-clamp-2">{topic}</span>
            </div>

            <%= for {index, question} <- cells do %>
              <button
                :if={Game.choosable?(@game, index) and @game.mode == :free}
                id={"question-#{index}"}
                phx-click="choose"
                phx-value-question={index}
                class="h-14 rounded-field border border-primary/30 bg-primary/10 text-lg font-bold tabular-nums text-primary transition hover:bg-primary hover:text-primary-content active:scale-95 phx-click-loading:opacity-50"
              >
                {question.points}
              </button>
              <div
                :if={question.result}
                id={"question-#{index}"}
                class="h-14 flex flex-col items-center justify-center rounded-field bg-base-200/60 px-1 text-xs text-base-content/50"
                title={"#{question.points} pts"}
              >
                <% correct = Game.correct_count(question) %>
                <.icon
                  name={if correct > 0, do: "hero-check", else: "hero-x-mark"}
                  class={["size-4", if(correct > 0, do: "text-success", else: "text-error")]}
                />
                <span class="tabular-nums">{correct}/{length(@game.players)} right</span>
              </div>
              <div
                :if={is_nil(question.result) and @game.mode == :ascending}
                id={"question-#{index}"}
                class={[
                  "h-14 grid place-items-center rounded-field border text-lg font-bold tabular-nums",
                  if(index == next,
                    do: "border-primary/40 bg-primary/10 text-primary",
                    else: "border-base-300 text-base-content/40"
                  )
                ]}
              >
                {question.points}
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :game, Game, required: true

  defp answering_panel(assigns) do
    assigns =
      assigns
      |> assign(:question, Game.current_question(assigns.game))
      |> assign(:player, Game.current_player(assigns.game))

    ~H"""
    <div
      id={"turn-#{@game.round}-#{@game.answered}"}
      class="rounded-box border border-base-300 bg-base-100 shadow-sm overflow-hidden reveal-pop"
    >
      <div class="bg-secondary text-secondary-content px-5 py-3 flex items-center gap-3">
        <.icon name="hero-hand-raised" class="size-5" />
        <p>
          Pass the device to <strong class="text-lg" id="current-player">{@player.name}</strong>
        </p>
        <span class="ml-auto text-sm opacity-80" id="answer-progress">
          {@game.answered + 1}/{length(@game.players)}
        </span>
      </div>
      <div class="p-5 sm:p-6 space-y-5">
        <.question_meta question={@question} />
        <p class="text-xl sm:text-2xl font-semibold leading-snug" id="question-text">
          {@question.text}
        </p>
        <div class="grid gap-3 sm:grid-cols-2">
          <button
            :for={{choice, i} <- Enum.with_index(@question.choices)}
            id={"choice-#{i}"}
            phx-click="answer"
            phx-value-choice={i}
            class="group flex items-center gap-3 rounded-field border border-base-300 bg-base-100 p-4 text-left transition hover:border-primary hover:bg-primary/5 active:scale-[0.98] phx-click-loading:opacity-50"
          >
            <span class="grid place-items-center size-8 shrink-0 rounded-full bg-base-200 font-semibold group-hover:bg-primary group-hover:text-primary-content transition">
              {<<?A + i>>}
            </span>
            <span>{choice}</span>
          </button>
        </div>
        <p class="text-sm text-base-content/60">
          Answers stay hidden until everyone has picked.
        </p>
      </div>
    </div>
    """
  end

  attr :game, Game, required: true

  defp reveal_panel(assigns) do
    question = Game.current_question(assigns.game)

    assigns =
      assigns
      |> assign(:question, question)
      |> assign(:chooser, Enum.at(assigns.game.players, question.result.chooser))
      |> assign(:last_round?, Enum.all?(assigns.game.questions, & &1.result))

    ~H"""
    <div
      class="rounded-box border border-base-300 bg-base-100 shadow-sm p-5 sm:p-6 space-y-5 reveal-pop"
      id="reveal"
    >
      <.question_meta question={@question} />
      <p class="text-xl font-semibold leading-snug">{@question.text}</p>
      <p class="text-sm text-base-content/60">Chosen by {@chooser.name}</p>

      <ul class="grid gap-2 sm:grid-cols-2">
        <li
          :for={{choice, i} <- Enum.with_index(@question.choices)}
          id={"reveal-choice-#{i}"}
          class={[
            "flex items-center gap-3 rounded-field border p-3",
            if(i == @question.correct,
              do: "border-success bg-success/15 font-semibold",
              else: "border-base-300 opacity-60"
            )
          ]}
        >
          <span class="grid place-items-center size-7 shrink-0 rounded-full bg-base-200 text-sm">
            {<<?A + i>>}
          </span>
          <span class="flex-1">{choice}</span>
          <.icon :if={i == @question.correct} name="hero-check-circle" class="size-6 text-success" />
        </li>
      </ul>

      <ul class="divide-y divide-base-300 rounded-field border border-base-300" id="round-results">
        <li
          :for={index <- Game.answer_order(@game)}
          id={"result-#{index}"}
          class="flex items-center gap-3 px-4 py-2.5"
        >
          <% correct? = Game.correct?(@game, index) %>
          <.icon
            name={if correct?, do: "hero-check-circle", else: "hero-x-circle"}
            class={["size-5", if(correct?, do: "text-success", else: "text-error")]}
          />
          <span class="font-medium">{Enum.at(@game.players, index).name}</span>
          <span class="text-sm text-base-content/60 truncate">
            picked {<<?A + Enum.at(@question.result.picks, index)>>}
          </span>
          <span class={[
            "ml-auto tabular-nums font-semibold",
            if(correct?, do: "text-success", else: "text-base-content/40")
          ]}>
            {if correct?, do: "+#{@question.points}", else: "+0"}
          </span>
        </li>
      </ul>

      <button class="btn btn-primary btn-block btn-lg" phx-click="next_round" id="next-round">
        {if @last_round?, do: "Show final results", else: "Back to the board"}
        <.icon name="hero-arrow-right" class="size-5" />
      </button>
    </div>
    """
  end

  attr :question, :map, required: true

  defp question_meta(assigns) do
    ~H"""
    <div class="flex items-center gap-2 text-sm">
      <span class="badge badge-outline">{@question.topic}</span>
      <span class="badge badge-primary" id="question-points">{@question.points} pts</span>
    </div>
    """
  end

  defp end_game_modal(assigns) do
    ~H"""
    <div
      id="end-game-modal"
      class="fixed inset-0 z-50 grid place-items-center p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="end-game-title"
      phx-window-keydown="cancel_end"
      phx-key="escape"
      phx-mounted={JS.focus(to: "#cancel-end")}
    >
      <div class="absolute inset-0 bg-base-content/40 backdrop-blur-sm" phx-click="cancel_end" />
      <div class="relative w-full max-w-md rounded-box border border-error/50 bg-base-100 shadow-xl p-5 sm:p-6 space-y-6 reveal-pop">
        <div class="flex items-start gap-3">
          <span class="grid place-items-center size-10 shrink-0 rounded-full bg-error text-error-content">
            <.icon name="hero-flag" class="size-5" />
          </span>
          <div>
            <h2 class="text-xl font-semibold" id="end-game-title">End the game?</h2>
            <p class="text-base-content/70">
              The final results are shown right away. A question that is not revealed yet will not be scored.
            </p>
            <p class="mt-2 text-sm text-base-content/60">
              Just need a break? Pause instead and continue later.
            </p>
          </div>
        </div>

        <div class="flex flex-wrap justify-end gap-2">
          <button class="btn btn-ghost" phx-click="cancel_end" id="cancel-end">Keep playing</button>
          <button class="btn" phx-click="pause" id="pause-instead">
            <.icon name="hero-pause" class="size-4" /> Pause
          </button>
          <button class="btn btn-error" phx-click="finish" id="confirm-end">
            <.icon name="hero-flag" class="size-4" /> End game
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :game, Game, required: true
  attr :resume_url, :string, required: true
  attr :qr_svg, :string, required: true
  attr :email_form, :any, required: true

  defp paused_panel(assigns) do
    ~H"""
    <div
      class="rounded-box border border-primary/50 bg-base-100 shadow-sm p-5 sm:p-6 space-y-6"
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

  defp final_panel(assigns) do
    standings = Game.standings(assigns.game)
    top = standings |> List.first() |> elem(0) |> Map.fetch!(:score)
    winners = for {p, _} <- standings, p.score == top, do: p.name

    assigns =
      assigns
      |> assign(:standings, standings)
      |> assign(:top, top)
      |> assign(:winners, winners)

    ~H"""
    <div
      class="rounded-box border border-primary/50 bg-base-100 shadow-sm p-6 space-y-6 text-center"
      id="final"
    >
      <div class="space-y-2">
        <span class="inline-grid place-items-center size-16 rounded-full bg-primary text-primary-content shadow">
          <.icon name="hero-trophy" class="size-8" />
        </span>
        <h2 class="text-3xl font-bold" id="winner">
          {if length(@winners) == 1,
            do: "#{hd(@winners)} wins!",
            else: "Tie: #{Enum.join(@winners, " & ")}"}
        </h2>
      </div>

      <ol class="space-y-2 text-left max-w-sm mx-auto" id="final-standings">
        <li
          :for={{{player, _index}, rank} <- Enum.with_index(@standings, 1)}
          class={[
            "flex items-center gap-3 rounded-field border px-4 py-3",
            if(player.score == @top, do: "border-primary bg-primary/10", else: "border-base-300")
          ]}
        >
          <span class="w-6 text-base-content/60 tabular-nums">{rank}.</span>
          <span class="flex-1 font-medium">{player.name}</span>
          <span class="font-semibold tabular-nums">{player.score}</span>
        </li>
      </ol>

      <div class="flex flex-wrap justify-center gap-2">
        <.link
          navigate={
            ~p"/categories/#{@game.category_id}/play?#{[players: Enum.map(@game.players, & &1.name), mode: @game.mode]}"
          }
          class="btn btn-primary"
          id="play-again"
        >
          <.icon name="hero-arrow-path" class="size-5" /> Play again
        </.link>
        <.link navigate={~p"/"} class="btn btn-ghost">Other categories</.link>
      </div>
    </div>
    """
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
         |> assign(:resume_url, url(~p"/games/#{view.id}"))
         |> assign(:qr_svg, nil)
         |> assign(:confirm_end, false)
         |> assign(:email_form, to_form(%{"email" => ""}, as: :resume))
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

  @impl true
  def handle_event("answer", %{"choice" => choice}, socket) do
    case Integer.parse(choice) do
      {choice, ""} -> run(socket, &Games.answer(&1, choice))
      _ -> {:noreply, socket}
    end
  end

  def handle_event("choose", %{"question" => index}, socket) do
    case Integer.parse(index) do
      {index, ""} -> run(socket, &Games.choose(&1, index))
      _ -> {:noreply, socket}
    end
  end

  def handle_event("next_round", _params, socket), do: run(socket, &Games.next_round/1)

  def handle_event("confirm_end", _params, socket),
    do: {:noreply, assign(socket, :confirm_end, true)}

  def handle_event("cancel_end", _params, socket),
    do: {:noreply, assign(socket, :confirm_end, false)}

  def handle_event("finish", _params, socket),
    do: socket |> assign(:confirm_end, false) |> run(&Games.finish/1)

  def handle_event("pause", _params, socket),
    do: socket |> assign(:confirm_end, false) |> run(&Games.pause/1)

  def handle_event("resume", _params, socket), do: run(socket, &Games.resume/1)

  def handle_event("send_email", %{"resume" => %{"email" => email}}, socket) do
    email = String.trim(email)

    if email =~ ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/ and String.length(email) <= 160 do
      case GameNotifier.deliver_resume_link(email, socket.assigns.resume_url, socket.assigns.game) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Resume link sent to #{email}.")
           |> assign(:email_form, to_form(%{"email" => ""}, as: :resume))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "The email could not be sent.")}
      end
    else
      form =
        to_form(%{"email" => email}, as: :resume, errors: [email: {"is not a valid email", []}])

      {:noreply, assign(socket, :email_form, form)}
    end
  end

  defp run(socket, fun) do
    case fun.(socket.assigns.game_id) do
      {:ok, view} ->
        {:noreply, assign_view(socket, view)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "That action is not possible right now.")}
    end
  end

  defp assign_view(socket, view) do
    socket
    |> assign(:status, view.status)
    |> assign(:game, view.game)
    |> assign(:page_title, "#{view.game.category_name} · Q#{view.game.round}")
    |> maybe_assign_qr()
  end

  # The QR code is only rendered (and computed) while paused.
  defp maybe_assign_qr(%{assigns: %{status: :paused, qr_svg: nil}} = socket) do
    svg = socket.assigns.resume_url |> EQRCode.encode() |> EQRCode.svg(width: 168)
    assign(socket, :qr_svg, svg)
  end

  defp maybe_assign_qr(socket), do: socket
end
