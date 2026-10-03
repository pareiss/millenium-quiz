defmodule MillenniumQuizWeb.HomeLive do
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.{Game, Games, Quiz}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="lg">
      <section class="text-center space-y-3 pt-4 pb-2">
        <p class="text-sm font-medium uppercase tracking-[0.2em] text-primary">Trivia night</p>
        <h1 class="text-4xl sm:text-5xl font-bold tracking-tight">Choose your format</h1>
        <p class="text-base-content/70 max-w-xl mx-auto">
          2 to 4 players, one device. Take turns choosing questions from the board: the harder the question, the more points it is worth.
        </p>
      </section>

      <section
        :if={@unfinished_games != []}
        id="unfinished-games"
        class="rounded-box border border-primary/40 bg-primary/5 p-4 space-y-3"
      >
        <h2 class="font-semibold flex items-center gap-2">
          <.icon name="hero-pause-circle" class="size-5 text-primary" /> Continue a game
        </h2>
        <ul class="divide-y divide-base-300">
          <li :for={g <- @unfinished_games} class="py-2 flex items-center gap-3">
            <div class="flex-1 min-w-0">
              <p class="font-medium truncate">{g.game.format_name}</p>
              <p class="text-sm text-base-content/60 truncate">
                {Enum.map_join(g.game.players, ", ", & &1.name)} · question {g.game.round}/{Game.total_rounds(
                  g.game
                )}
              </p>
            </div>
            <.link
              navigate={~p"/games/#{g.id}"}
              class="btn btn-sm btn-primary"
              id={"continue-#{g.id}"}
            >
              Continue
            </.link>
          </li>
        </ul>
      </section>

      <div
        id="known-games"
        phx-hook=".KnownGames"
        class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3"
      >
        <.link
          :for={%{format: format, topics: topics, questions: questions} <- @formats}
          navigate={~p"/formats/#{format.id}/play"}
          id={"format-#{format.id}"}
          class="group relative overflow-hidden rounded-box border border-base-300 bg-base-100 p-5 shadow-sm transition hover:-translate-y-0.5 hover:border-primary hover:shadow-md"
        >
          <div class="absolute -right-6 -top-6 size-24 rounded-full bg-primary/10 transition group-hover:scale-125" />
          <h2 class="relative text-xl font-semibold">{format.name}</h2>
          <p :if={format.description} class="relative mt-1 text-sm text-base-content/70 line-clamp-3">
            {format.description}
          </p>
          <div class="relative mt-4 flex flex-wrap items-center gap-x-2 gap-y-1.5 text-xs text-base-content/60">
            <span class="badge badge-ghost badge-sm whitespace-nowrap">{display_date(format.date)}</span>
            <span class="badge badge-ghost badge-sm whitespace-nowrap">{topics} topics</span>
            <span class="badge badge-ghost badge-sm whitespace-nowrap">{questions} questions</span>
            <span class="ml-auto whitespace-nowrap text-primary font-medium group-hover:translate-x-0.5 transition">
              Play <span aria-hidden="true">&rarr;</span>
            </span>
          </div>
        </.link>

        <div
          :if={@formats == []}
          class="sm:col-span-2 lg:col-span-3 rounded-box border border-dashed border-base-300 p-10 text-center text-base-content/60"
        >
          No playable formats yet. An admin needs to add a format with at least two topics and one question.
        </div>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".KnownGames">
        // Games started on this device are remembered in localStorage (see
        // GameLive's .RememberGame hook) so they can be continued from here.
        export default {
          mounted() {
            let ids = []
            try { ids = JSON.parse(localStorage.getItem("mq:games") || "[]") } catch (_e) {}
            if (ids.length > 0) this.pushEvent("known_games", {ids})
          }
        }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Formats")
     |> assign(:formats, Quiz.list_playable_formats())
     |> assign(:unfinished_games, [])}
  end

  @impl true
  def handle_event("known_games", %{"ids" => ids}, socket) when is_list(ids) do
    ids = ids |> Enum.filter(&is_binary/1) |> Enum.take(20)
    {:noreply, assign(socket, :unfinished_games, Games.list_unfinished_games(ids))}
  end
end
