defmodule MillenniumQuizWeb.NewGameLive do
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.{Game, Games, Quiz}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.link navigate={~p"/"} class="text-sm text-base-content/60 hover:text-base-content">
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

        <.form for={@form} id="players-form" phx-change="change" phx-submit="start" class="space-y-3">
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
                maxlength="24"
                autocomplete="off"
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
     |> assign_names(["", ""])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # "Play again" passes the previous names: /formats/1/play?players[]=A&players[]=B
    socket = assign_mode(socket, params["mode"])

    case params do
      %{"players" => names} when is_list(names) ->
        {:noreply, assign_names(socket, Enum.take(names, Game.max_players()))}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change", %{"names" => names} = params, socket) do
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
    names = List.delete_at(socket.assigns.names, String.to_integer(index))
    {:noreply, assign_names(socket, names)}
  end

  def handle_event("start", %{"names" => names} = params, socket) do
    socket = socket |> assign_mode(params["mode"]) |> assign_names(names)

    with :ok <- validate_unique(names),
         {:ok, game_id} <-
           Games.create_game(socket.assigns.format.id, names, mode: socket.assigns.mode) do
      {:noreply, push_navigate(socket, to: ~p"/games/#{game_id}")}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  defp validate_unique(names) do
    trimmed = names |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    normalized = Enum.map(trimmed, &String.downcase/1)

    if Enum.uniq(normalized) == normalized, do: :ok, else: {:error, :duplicate_names}
  end

  defp error_message(:blank_player_name), do: "Every player needs a name."
  defp error_message(:duplicate_names), do: "Player names must be different."
  defp error_message(:invalid_player_count), do: "A game needs 2 to 4 players."
  defp error_message(:invalid_mode), do: "Choose a game mode."
  defp error_message(:no_questions), do: "This format has no questions yet."
  defp error_message(_), do: "The game could not be started."

  defp assign_mode(socket, mode) do
    case Game.parse_mode(mode) do
      {:ok, mode} -> assign(socket, :mode, to_string(mode))
      {:error, _} -> socket
    end
  end

  defp assign_names(socket, names) do
    socket
    |> assign(:names, names)
    |> assign(:form, to_form(%{"names" => names}))
  end
end
