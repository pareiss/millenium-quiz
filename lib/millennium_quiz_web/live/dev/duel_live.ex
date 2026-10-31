if Application.compile_env(:millennium_quiz, :dev_routes) do
  defmodule MillenniumQuizWeb.Dev.DuelLive do
    @moduledoc """
    Dev-only style guide of the duel components (`/dev/duel`, only routed and
    compiled with `dev_routes`). Open it with `?theme=duel-dark` or `?theme=duel-light`.
    """
    use MillenniumQuizWeb, :live_view

    @avatars ~w(elemental-hero-stratos blackwing-armor-master blackwing-bora-the-spear blackwing-shura-the-blue-flame)
    @names ["Yugi", "Kaiba the Seto with a very long name indeed", "Joey", "Mai"]

    def mount(_params, _session, socket) do
      {:ok, assign(socket, names: @names, avatars: @avatars)}
    end

    def render(assigns) do
      ~H"""
      <Layouts.app flash={@flash} width="lg">
        <h1 class="mb-4 text-2xl">Duel components</h1>
        <.orb_rail id="rail" total={16} current={3} class="mb-6" />

        <section :for={n <- [2, 3, 4]} id={"players-#{n}"} class="mb-6">
          <h2 class="mb-2 text-lg">{n} players</h2>
          <div class={[
            "grid gap-2",
            n == 2 && "sm:grid-cols-2",
            n == 3 && "sm:grid-cols-3",
            n == 4 && "sm:grid-cols-2 lg:grid-cols-4"
          ]}>
            <.lp_gauge
              :for={{name, i} <- @names |> Enum.take(n) |> Enum.with_index()}
              id={"gauge-#{n}-#{i}"}
              name={name}
              avatar={Enum.at(@avatars, i)}
              lp={Enum.at([4000, 1200, 30, 0], i)}
              start_lp={4000}
              player={i}
              active={i == 0}
              status={if i == 1, do: :hit, else: if(i == 3, do: :eliminated, else: :alive)}
              damage={if i == 1, do: 800}
            />
          </div>
        </section>

        <section id="widths" class="mb-6">
          <h2 class="mb-2 text-lg">Widths</h2>
          <div :for={w <- [420, 300, 180, 90]} class="mb-2" style={"width:#{w}px;max-width:100%"}>
            <.lp_gauge
              id={"w-#{w}"}
              name="Yugi Muto"
              avatar="elemental-hero-stratos"
              lp={2500}
              start_lp={4000}
              player={0}
            />
          </div>
          <p class="mt-4 text-lg"><.atk_label value="1600" /></p>
        </section>
      </Layouts.app>
      """
    end
  end
end
