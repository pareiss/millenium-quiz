defmodule MillenniumQuizWeb.NewGameLive do
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.{Game, Games, Quiz, RateLimit}
  alias MillenniumQuizWeb.ClientIP

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.link
        navigate={~p"/"}
        class="inline-flex items-center text-sm text-base-content/60 hover:text-base-content pointer-coarse:min-h-11"
      >
        <span aria-hidden="true">&larr;</span> All formats
      </.link>

      <div class="rounded-box border border-base-300 bg-base-100 p-6 sm:p-8 shadow-sm space-y-6">
        <div>
          <p class="text-sm font-medium uppercase tracking-[0.2em] text-primary">New game</p>
          <h1 class="text-3xl font-bold tracking-tight">{@format.name}</h1>
          <p class="text-sm text-base-content/60">Card texts as of {display_date(@format.date)}</p>
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
          <p class="font-medium">Who is playing? ({@min}–{@max} players)</p>
          <div :for={{name, i} <- Enum.with_index(@names)} class="flex items-start gap-2">
            <span class="mt-2 grid place-items-center size-8 shrink-0 rounded-full bg-secondary text-secondary-content text-sm font-semibold">
              {i + 1}
            </span>
            <div class="flex-1">
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
              class="btn btn-ghost btn-square mt-0.5"
              phx-click="remove"
              phx-value-index={i}
              id={"remove-player-#{i}"}
              aria-label={"Remove player #{i + 1}"}
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <fieldset class="space-y-2 pt-3">
            <legend class="font-medium mb-2">Game mode</legend>
            <div class="grid gap-3 sm:grid-cols-2">
              <label
                :for={mode <- @modes}
                id={"mode-#{mode}"}
                class="flex cursor-pointer items-start gap-3 rounded-field border border-base-300 p-4 transition hover:border-primary/60 has-checked:border-primary has-checked:bg-primary/5"
              >
                <input
                  type="radio"
                  name="mode"
                  value={mode}
                  checked={@mode == to_string(mode)}
                  class="radio radio-primary radio-sm mt-0.5"
                />
                <span>
                  <span class="block font-semibold">{Game.mode_name(mode)}</span>
                  <span class="block text-sm text-base-content/70">{Game.mode_description(mode)}</span>
                </span>
              </label>
            </div>
          </fieldset>

          <p :if={@error} class="text-sm text-error flex items-center gap-2" id="players-error">
            <.icon name="hero-exclamation-circle" class="size-5" /> {@error}
          </p>

          <div class="flex flex-wrap gap-2 pt-2">
            <button
              :if={length(@names) < @max}
              type="button"
              class="btn btn-ghost"
              phx-click="add"
              id="add-player"
            >
              <.icon name="hero-user-plus" class="size-5" /> Add player
            </button>
            <div class="flex-1" />
            <button
              type="submit"
              class="btn btn-primary"
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
     |> assign(:error, nil)
     # connect_info is only readable in mount.
     |> assign(:client_ip, ClientIP.from_socket(socket))
     |> assign_names(["", ""])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # "Play again" passes the previous names: /formats/1/play?players[]=A&players[]=B
    socket = assign_mode(socket, params["mode"])

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
     |> assign_names(names)}
  end

  def handle_event("add", _params, socket) do
    names = socket.assigns.names
    names = if length(names) < Game.max_players(), do: names ++ [""], else: names
    {:noreply, assign_names(socket, names)}
  end

  def handle_event("remove", %{"index" => index}, socket) do
    case Integer.parse(to_string(index)) do
      {index, ""} -> {:noreply, assign_names(socket, List.delete_at(socket.assigns.names, index))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("start", %{"names" => names} = params, socket)
      when is_list(names) and length(names) <= 20 do
    names = Enum.filter(names, &is_binary/1)
    socket = socket |> assign_mode(params["mode"]) |> assign_names(names)

    with :ok <- validate_unique(names),
         :ok <- validate_name_lengths(names),
         :ok <- rate_limit(socket),
         {:ok, game_id} <-
           Games.create_game(socket.assigns.format.id, names, mode: socket.assigns.mode) do
      {:noreply, push_navigate(socket, to: ~p"/games/#{game_id}")}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
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
  defp error_message(:invalid_mode), do: "Choose a game mode."

  defp error_message(:full),
    do: "The site is full right now. Please try again in a while."

  defp error_message(:insert_failed),
    do: "The game could not be saved right now. Please try again in a while."

  defp error_message(:no_questions), do: "This format has no questions yet."
  defp error_message(_), do: "The game could not be started."

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
  end
end
