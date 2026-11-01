defmodule MillenniumQuizWeb.NewGameLive do
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.{Avatars, Game, Games, Quiz, RateLimit}
  alias MillenniumQuizWeb.ClientIP

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.link
        navigate={~p"/"}
        class="duel-back inline-flex items-center text-sm text-base-content/70 hover:text-base-content pointer-coarse:min-h-11"
      >
        <span aria-hidden="true">&larr;</span> All formats
      </.link>

      <div
        id="new-game-panel"
        class="duel-plate duel-sheet duel-surface rounded-box border border-base-300 bg-base-100 p-4 sm:p-8 shadow-sm space-y-6"
      >
        <div>
          <p class="duel-eyebrow text-sm font-medium uppercase tracking-[0.2em] text-primary">
            New game
          </p>
          <h1 class="duel-title text-3xl font-bold tracking-tight">{@format.name}</h1>
          <p class="text-sm text-base-content/70">Card texts as of {display_date(@format.date)}</p>
          <p class="mt-1 text-base-content/70">
            {length(@format.topics)} topics: {Enum.map_join(@format.topics, ", ", & &1.name)}
          </p>
        </div>

        <.form
          for={@form}
          id="players-form"
          phx-hook=".NextOnEnter"
          phx-change="change"
          phx-submit="start"
          class="space-y-3"
        >
          <p class="duel-legend font-medium">Who is playing? ({@min}–{@max} players)</p>
          <div :for={{name, i} <- Enum.with_index(@names)} id={"player-row-#{i}"}>
            <div class="flex items-center gap-2">
              <button
                type="button"
                id={"avatar-button-#{i}"}
                phx-click="toggle_avatar"
                phx-value-index={i}
                aria-label={"Player #{i + 1}'s picture: #{avatar_label(@labels, Enum.at(@avatars, i))}, change"}
                aria-expanded={to_string(@open == i)}
                aria-controls={"avatar-panel-#{i}"}
                class="duel-avatar-btn relative shrink-0 cursor-pointer rounded-full size-14 transition hover:scale-105 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
              >
                <.synchro_ring class="size-14">
                  <.avatar
                    slug={Enum.at(@avatars, i)}
                    title={avatar_label(@labels, Enum.at(@avatars, i))}
                    crop={@crops[Enum.at(@avatars, i)]}
                    class="size-full"
                  />
                </.synchro_ring>
                <span class="duel-avatar-no absolute -bottom-0.5 -right-0.5 grid place-items-center size-5 rounded-full bg-secondary text-secondary-content text-xs font-semibold">
                  {i + 1}
                </span>
              </button>
              <div class="flex-1 min-w-0">
                <.input
                  name="names[]"
                  id={"player-name-#{i}"}
                  value={name}
                  placeholder={"Player #{i + 1}"}
                  maxlength={Game.max_name_length()}
                  autocomplete="off"
                  autocapitalize="words"
                  autocorrect="off"
                  spellcheck="false"
                  enterkeyhint="next"
                  phx-debounce="200"
                />
              </div>
              <button
                :if={length(@names) > @min}
                type="button"
                class="btn btn-ghost btn-square pointer-coarse:size-11"
                phx-click="remove"
                phx-value-index={i}
                id={"remove-player-#{i}"}
                aria-label={"Remove player #{i + 1}"}
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <div
              :if={@open == i}
              id={"avatar-panel-#{i}"}
              phx-window-keydown="close_avatar"
              phx-key="Escape"
              class="duel-plate duel-picker mt-2 rounded-box border border-base-300 bg-base-200/50 p-2 space-y-2"
            >
              <div class="flex items-center justify-between gap-2">
                <p class="duel-legend text-sm font-medium">Pick a picture for player {i + 1}</p>
                <button
                  type="button"
                  id={"avatar-random-#{i}"}
                  phx-click="random_avatar"
                  phx-value-index={i}
                  class="btn btn-ghost btn-sm pointer-coarse:min-h-11"
                >
                  <.icon name="hero-arrow-path" class="size-4" /> Another one
                </button>
              </div>
              <div
                role="group"
                aria-label={"Pictures for player #{i + 1}"}
                class="grid grid-cols-[repeat(auto-fill,minmax(2.75rem,1fr))] gap-1 max-h-56 overflow-y-auto overscroll-contain p-1"
              >
                <button
                  :for={slug <- @pool}
                  type="button"
                  id={"avatar-choice-#{i}-#{slug}"}
                  phx-click="pick_avatar"
                  phx-value-index={i}
                  phx-value-slug={slug}
                  disabled={taken_by_other?(@avatars, i, slug)}
                  aria-pressed={to_string(Enum.at(@avatars, i) == slug)}
                  aria-label={
                    avatar_label(@labels, slug) <>
                      if(taken_by_other?(@avatars, i, slug), do: " (taken)", else: "")
                  }
                  class={
                    [
                      "duel-avatar-choice relative aspect-square min-h-11 rounded-full p-0.5 transition",
                      Enum.at(@avatars, i) == slug && "duel-picked ring-2 ring-primary bg-primary/20",
                      # a free picture lights up under the mouse; a taken one shows "not allowed"
                      not taken_by_other?(@avatars, i, slug) &&
                        "cursor-pointer hover:bg-primary/20 hover:ring-2 hover:ring-primary/60 hover:scale-105",
                      taken_by_other?(@avatars, i, slug) && "opacity-30 grayscale cursor-not-allowed"
                    ]
                  }
                >
                  <%!-- the chosen picture wears the Synchro ring (the duel themes hide the
                       plain ring); in the other themes the plain ring stays --%>
                  <.avatar
                    slug={slug}
                    title={avatar_label(@labels, slug)}
                    crop={@crops[slug]}
                    class="size-full"
                  />
                  <svg
                    :if={Enum.at(@avatars, i) == slug}
                    viewBox="0 0 64 64"
                    class="duel-picked-ring pointer-events-none absolute -inset-[0.3rem] size-[calc(100%+0.6rem)] overflow-visible"
                    aria-hidden="true"
                    focusable="false"
                  >
                    <use href="#duel-ring" />
                  </svg>
                </button>
              </div>
            </div>
          </div>

          <div :if={length(@names) < @max} class="flex">
            <button
              type="button"
              class="duel-btn btn btn-ghost"
              phx-click="add"
              id="add-player"
            >
              <.icon name="hero-user-plus" class="size-5" /> Add player
            </button>
          </div>

          <fieldset id="mode-choice" class="space-y-2 pt-3">
            <legend class="duel-legend font-medium mb-2">Game mode</legend>
            <div class="grid gap-3 sm:grid-cols-2">
              <label
                :for={mode <- @modes}
                id={"mode-#{mode}"}
                class="duel-plate duel-option flex cursor-pointer items-start gap-3 rounded-field border border-base-300 p-4 transition hover:border-primary/60 has-checked:border-primary has-checked:bg-primary/5"
              >
                <input
                  type="radio"
                  name="mode"
                  value={mode}
                  checked={@mode == to_string(mode)}
                  class="radio radio-primary radio-sm mt-0.5"
                />
                <span class="min-w-0">
                  <span class="duel-title block font-semibold">{Game.mode_name(mode)}</span>
                  <span class="block text-sm text-base-content/70">{Game.mode_description(mode)}</span>
                </span>
              </label>
            </div>
          </fieldset>

          <fieldset class="space-y-2 pt-3" id="lp-choice">
            <legend class="duel-legend font-medium mb-2">Life Points</legend>
            <div class="grid gap-3 sm:grid-cols-2">
              <label
                :for={lp <- @start_lps}
                id={"lp-choice-#{lp}"}
                class="duel-plate duel-option flex cursor-pointer items-start gap-3 rounded-field border border-base-300 p-4 transition hover:border-primary/60 has-checked:border-primary has-checked:bg-primary/5 pointer-coarse:min-h-11"
              >
                <input
                  type="radio"
                  name="start_lp"
                  value={lp}
                  checked={@start_lp == to_string(lp)}
                  class="radio radio-primary radio-sm mt-0.5"
                />
                <span class="min-w-0">
                  <span class="duel-title block font-semibold tabular-nums">{lp} LP</span>
                  <span class="block text-sm text-base-content/70">{lp_description(lp)}</span>
                </span>
              </label>
            </div>
          </fieldset>

          <p :if={@error} class="text-sm text-error flex items-center gap-2" id="players-error">
            <.icon name="hero-exclamation-circle" class="size-5" /> {@error}
          </p>

          <div class="flex justify-end pt-2">
            <button
              type="submit"
              class="duel-btn btn btn-primary"
              id="start-game"
              phx-disable-with="Shuffling…"
            >
              Start game <.icon name="hero-play" class="size-5" />
            </button>
          </div>
        </.form>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".NextOnEnter">
        // On phones the keyboard's Enter ("Next") must not start the game with
        // the names typed so far: it moves to the next name field, and from the
        // last one just closes the keyboard. Desktop keeps Enter = submit.
        export default {
          mounted() {
            this.onKeydown = (e) => {
              if (e.key !== "Enter" || e.isComposing) return
              if (!window.matchMedia("(pointer: coarse)").matches) return
              const field = e.target
              if (!(field instanceof HTMLInputElement) || field.name !== "names[]") return
              e.preventDefault()
              const fields = [...this.el.querySelectorAll('input[name="names[]"]')]
              const next = fields[fields.indexOf(field) + 1]
              if (next) next.focus()
              else field.blur()
            }
            this.el.addEventListener("keydown", this.onKeydown)
          },
          destroyed() {
            this.el.removeEventListener("keydown", this.onKeydown)
          }
        }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    format = Quiz.get_format!(id)

    {:ok,
     socket
     |> assign(:page_title, "New game · #{format.name}")
     |> assign(:format, format)
     |> assign(:min, Game.min_players())
     |> assign(:max, Game.max_players())
     |> assign(:modes, Game.modes())
     |> assign(:mode, "free")
     |> assign(:start_lps, Game.start_lps())
     |> assign(:start_lp, to_string(Game.default_start_lp()))
     |> assign(:error, nil)
     |> assign(:open, nil)
     |> assign(:avatars, [])
     |> assign_pool(format)
     # connect_info is only readable in mount.
     |> assign(:client_ip, ClientIP.from_socket(socket))
     |> assign_names(["", ""])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # "Play again" passes the previous names: /formats/1/play?players[]=A&players[]=B
    socket = socket |> assign_mode(params["mode"]) |> assign_start_lp(params["start_lp"])

    case params do
      %{"players" => names} when is_list(names) ->
        names = names |> Enum.filter(&is_binary/1) |> Enum.take(Game.max_players())
        {:noreply, assign_names(socket, names)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change", %{"names" => names} = params, socket) when is_list(names) do
    # assign_names/2 bounds the list and the names; the browser is not trusted.
    {:noreply,
     socket
     |> assign(:error, nil)
     |> assign_mode(params["mode"])
     |> assign_start_lp(params["start_lp"])
     |> assign_names(names)}
  end

  def handle_event("add", _params, socket) do
    names = socket.assigns.names
    names = if length(names) < Game.max_players(), do: names ++ [""], else: names
    {:noreply, assign_names(socket, names)}
  end

  def handle_event("remove", %{"index" => index}, socket) do
    with {:ok, index} <- parse_index(index, socket) do
      {:noreply,
       socket
       |> assign(:open, nil)
       |> assign(:avatars, List.delete_at(socket.assigns.avatars, index))
       |> assign_names(List.delete_at(socket.assigns.names, index))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_avatar", %{"index" => index}, socket) do
    case parse_index(index, socket) do
      {:ok, i} ->
        {:noreply, assign(socket, :open, if(socket.assigns.open == i, do: nil, else: i))}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("close_avatar", _params, socket), do: {:noreply, assign(socket, :open, nil)}

  def handle_event("pick_avatar", %{"index" => index, "slug" => slug}, socket) do
    with {:ok, i} <- parse_index(index, socket),
         true <- is_binary(slug) and slug in socket.assigns.pool,
         false <- taken_by_other?(socket.assigns.avatars, i, slug) do
      {:noreply,
       socket
       |> assign(:avatars, List.replace_at(socket.assigns.avatars, i, slug))
       |> assign(:open, nil)
       |> assign(:error, nil)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("random_avatar", %{"index" => index}, socket) do
    with {:ok, i} <- parse_index(index, socket) do
      avatars = socket.assigns.avatars
      others = List.delete_at(avatars, i)
      free = socket.assigns.pool -- [Enum.at(avatars, i) | others]

      case free do
        [] ->
          {:noreply, socket}

        free ->
          {:noreply, assign(socket, :avatars, List.replace_at(avatars, i, Enum.random(free)))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("start", %{"names" => names} = params, socket)
      when is_list(names) and length(names) <= 20 do
    names = Enum.filter(names, &is_binary/1)

    socket =
      socket
      |> assign_mode(params["mode"])
      |> assign_start_lp(params["start_lp"])
      |> assign_names(names)

    with {:ok, start_lp} <- start_lp_param(params, socket),
         :ok <- validate_unique(names),
         :ok <- validate_name_lengths(names),
         :ok <- rate_limit(socket),
         {:ok, game_id} <-
           Games.create_game(socket.assigns.format.id, names,
             mode: socket.assigns.mode,
             start_lp: start_lp,
             avatars: socket.assigns.avatars
           ) do
      {:noreply, push_navigate(socket, to: ~p"/games/#{game_id}")}
    else
      {:error, :invalid_avatar} ->
        # The format's pictures changed since this page opened: start over with
        # the current ones, keeping the pictures that are still in the pool.
        {:noreply,
         socket
         |> reload_pool()
         |> assign(:error, error_message(:invalid_avatar))}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  # Malformed input from the browser is ignored.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp rate_limit(socket) do
    limits = [create_ip: socket.assigns.client_ip, create_global: :all]

    case RateLimit.check_all(limits) do
      :ok -> :ok
      {:error, retry_after_ms} -> {:error, {:rate_limited, retry_after_ms}}
    end
  end

  defp validate_name_lengths(names) do
    if Enum.all?(names, &(String.length(String.trim(&1)) <= Game.max_name_length())),
      do: :ok,
      else: {:error, :player_name_too_long}
  end

  defp validate_unique(names) do
    trimmed = names |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    normalized = Enum.map(trimmed, &String.downcase/1)

    if Enum.uniq(normalized) == normalized, do: :ok, else: {:error, :duplicate_names}
  end

  defp error_message({:rate_limited, retry_after_ms}),
    do:
      "You have started a lot of games. Please try again in #{RateLimit.describe_wait(retry_after_ms)}."

  defp error_message(:player_name_too_long),
    do: "Player names can have at most #{Game.max_name_length()} characters."

  defp error_message(:blank_player_name), do: "Every player needs a name."
  defp error_message(:duplicate_names), do: "Player names must be different."
  defp error_message(:invalid_player_count), do: "A game needs 2 to 4 players."

  defp error_message(:invalid_avatar),
    do: "Some pictures are not available any more. Please check them and start again."

  defp error_message(:duplicate_avatars),
    do: "Every player needs a different picture."

  defp error_message(:invalid_mode), do: "Choose a game mode."
  defp error_message(:invalid_start_lp), do: "Choose 4000 or 8000 life points."

  defp error_message(:full),
    do: "The site is full right now. Please try again in a while."

  defp error_message(:insert_failed),
    do: "The game could not be saved right now. Please try again in a while."

  defp error_message(:no_questions), do: "This format has no questions yet."
  defp error_message(_), do: "The game could not be started."

  # A forged value is refused with a message (the form never sends one); a
  # missing field keeps the choice made so far.
  defp start_lp_param(%{"start_lp" => value}, _socket), do: Game.parse_start_lp(value)
  defp start_lp_param(_params, socket), do: Game.parse_start_lp(socket.assigns.start_lp)

  defp lp_description(4000), do: "A quick duel. Three or four wrong answers can end a player."
  defp lp_description(8000), do: "A long duel. Everyone can take more hits."

  defp assign_start_lp(socket, lp) do
    case Game.parse_start_lp(lp) do
      {:ok, lp} -> assign(socket, :start_lp, to_string(lp))
      {:error, _} -> socket
    end
  end

  defp assign_mode(socket, mode) do
    case Game.parse_mode(mode) do
      {:ok, mode} -> assign(socket, :mode, to_string(mode))
      {:error, _} -> socket
    end
  end

  # Bounded however much the browser sends: at most max_players inputs, and
  # names cut far above the 24 characters that `start` validates (so that
  # message still shows).
  @max_input_length 100

  defp assign_names(socket, names) do
    names =
      names
      |> Stream.filter(&is_binary/1)
      |> Enum.take(Game.max_players())
      |> Enum.map(&String.slice(&1, 0, @max_input_length))

    socket
    |> assign(:names, names)
    |> assign(:form, to_form(%{"names" => names}))
    |> fill_avatars()
    |> then(fn socket ->
      # a panel for a player who is gone closes
      if socket.assigns.open && socket.assigns.open >= length(names),
        do: assign(socket, :open, nil),
        else: socket
    end)
  end

  # One picture per name: those already chosen stay (as long as they are in the
  # pool), new players get different random ones out of the rest.
  defp fill_avatars(socket) do
    %{names: names, avatars: avatars, pool: pool} = socket.assigns
    count = length(names)
    chosen = avatars |> Enum.take(count) |> Enum.map(&if(&1 in pool, do: &1))
    assign(socket, :avatars, Avatars.assign(count, &Enum.shuffle/1, pool, chosen))
  end

  defp assign_pool(socket, format) do
    cards = Quiz.avatar_cards(format.id)

    labels =
      Map.new(cards, &{Avatars.card_slug(&1.id), &1.name})

    pool = Avatars.pool(format)

    socket
    |> assign(:pool, pool)
    |> assign(:labels, labels)
    |> assign(:crops, Quiz.avatar_crops(pool, defaults: true))
  end

  defp reload_pool(socket) do
    format = Quiz.get_format!(socket.assigns.format.id)
    socket |> assign(:format, format) |> assign_pool(format) |> fill_avatars()
  end

  defp avatar_label(labels, slug), do: Map.get(labels, slug) || Avatars.name(slug) || "a picture"

  defp taken_by_other?(avatars, i, slug),
    do: avatars |> List.delete_at(i) |> Enum.member?(slug)

  # An index of an existing name row; anything else from the browser is ignored.
  defp parse_index(value, socket) when is_binary(value) or is_integer(value) do
    case Integer.parse(to_string(value)) do
      {i, ""} when i >= 0 -> if i < length(socket.assigns.names), do: {:ok, i}, else: :error
      _ -> :error
    end
  end

  defp parse_index(_value, _socket), do: :error
end
