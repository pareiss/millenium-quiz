if Application.compile_env(:millennium_quiz, :dev_routes) do
  defmodule MillenniumQuizWeb.Dev.BoardLive do
    @moduledoc """
    Dev-only preview of the board view (`/dev/board`, only routed and compiled with
    `dev_routes`): `DuelComponents.duel_board/1` and `board_button/1` on fixture
    boards in the shape of its data contract. Pick a board with `?board=goat | edison
    | pendulum | modern | empty`; the dialog opens by itself (`?open=0` keeps it
    closed). Open it with `?theme=duel-dark` or `?theme=duel-light`.

    The fixtures use the artwork crops in `priv/static/images/avatars` where a card
    has one and no artwork (the frame and an initial) otherwise.
    """
    use MillenniumQuizWeb, :live_view

    import MillenniumQuizWeb.DuelComponents, only: [duel_board: 1, board_button: 1]

    @names %{1 => "Mika", 2 => "Tobias"}

    @fixtures [
      {"goat", "Goat (no Extra Monster Zones)"},
      {"edison", "Edison (hand, graveyard)"},
      {"pendulum", "Pendulum era (scales)"},
      {"modern", "Modern (Extra Monster Zones, Xyz, counters)"},
      {"empty", "Nearly empty"}
    ]

    def mount(_params, _session, socket) do
      {:ok, assign(socket, names: @names, fixtures: @fixtures, selected: nil)}
    end

    def handle_params(params, _uri, socket) do
      key =
        if params["board"] in Enum.map(@fixtures, &elem(&1, 0)), do: params["board"], else: "goat"

      {:noreply,
       assign(socket,
         key: key,
         board: board(key),
         open: params["open"] != "0",
         selected: nil
       )}
    end

    def handle_event("open", _params, socket), do: {:noreply, assign(socket, open: true)}

    def handle_event("close", _params, socket),
      do: {:noreply, assign(socket, open: false, selected: nil)}

    def handle_event("card", %{"key" => key}, socket) do
      selected = if socket.assigns.selected == key, do: nil, else: key
      {:noreply, assign(socket, selected: selected)}
    end

    def render(assigns) do
      assigns = assign(assigns, :card, selected_card(assigns.board, assigns.selected))

      ~H"""
      <Layouts.app flash={@flash} width="lg">
        <h1 class="mb-4 text-2xl">Board view</h1>
        <nav id="board-fixtures" class="mb-4 flex flex-wrap gap-2" aria-label="Fixture boards">
          <.link
            :for={{key, label} <- @fixtures}
            id={"fixture-#{key}"}
            patch={~p"/dev/board?board=#{key}"}
            class={["btn btn-sm", if(key == @key, do: "btn-primary", else: "btn-outline")]}
          >
            {label}
          </.link>
        </nav>
        <.board_button id="board-button" board={@board} on_click="open" />

        <.duel_board
          :if={@open}
          id="board-dialog"
          board={@board}
          names={@names}
          on_close="close"
          on_card="card"
          selected={@selected}
        >
          <:detail :if={@card}>
            <div id="board-detail" class="flex flex-col gap-2">
              <img
                :if={@card["art"]}
                src={@card["art"]}
                alt=""
                class="aspect-square w-full object-cover"
              />
              <h3 class="text-lg font-bold">{@card["name"]}</h3>
              <p class="text-sm">
                {@card["kind"]}<span :if={@card["atk"]}> · ATK {@card["atk"]}</span><span :if={
                  @card["def"]
                }> · DEF {@card["def"]}</span>
              </p>
            </div>
          </:detail>
        </.duel_board>
      </Layouts.app>
      """
    end

    defp selected_card(_board, nil), do: nil

    defp selected_card(board, key) do
      case String.split(key, ":") do
        ["emz", i] ->
          Enum.at(board["emz"], String.to_integer(i))

        ["p" <> seat, "field", _] ->
          seat_player(board, seat)["field"]

        ["p" <> seat, zone, i] ->
          Enum.at(seat_player(board, seat)[zone], String.to_integer(i))
      end
    end

    defp seat_player(board, seat), do: Enum.at(board["players"], String.to_integer(seat) - 1)

    # ---- fixtures: the data contract of DuelComponents.duel_board/1 ----

    @avatar_dir "/images/avatars/"

    defp card(name, kind, opts) do
      slug = opts[:art]

      %{
        "name" => name,
        "kind" => kind,
        "atk" => opts[:atk],
        "def" => opts[:def],
        "level" => opts[:level],
        "pos" => opts[:pos] || "atk",
        "overlay" => opts[:overlay] || 0,
        "counters" => opts[:counters] || 0,
        "art" => slug && @avatar_dir <> slug <> ".jpg",
        "scale" => opts[:scale] || false,
        "password" => opts[:password] || 0
      }
    end

    defp mon(name, kind, atk, df, opts \\ []),
      do: card(name, kind, [atk: atk, def: df] ++ opts)

    defp spell(name, opts \\ []), do: card(name, "spell", opts)
    defp trap(name, opts \\ []), do: card(name, "trap", opts)
    defp set(name, kind), do: card(name, kind, pos: "set")

    defp player(lp, opts) do
      Map.merge(
        %{
          "lp" => lp,
          "name" => nil,
          "monsters" => List.duplicate(nil, 5),
          "spells" => List.duplicate(nil, 5),
          "field" => nil,
          "hand" => [],
          "grave" => [],
          "banished" => [],
          "extra" => [],
          "deck" => 0
        },
        Map.new(opts, fn {k, v} -> {to_string(k), v} end)
      )
    end

    defp board("goat") do
      %{
        "rule" => "mr1_2",
        "turn" => 3,
        "phase" => "main1",
        "turn_player" => 1,
        "emz" => [nil, nil],
        "players" => [
          player(6200,
            monsters: [
              nil,
              mon("Chaos Sorcerer", "effect", 2300, 2000, art: "chaos-sorcerer"),
              mon("Don Zaloog", "effect", 1400, 1500, art: "don-zaloog"),
              nil,
              nil
            ],
            spells: [nil, nil, set("Heavy Storm", "spell"), nil, nil],
            grave: [
              mon("Injection Fairy Lily", "normal", 400, 1500, art: "injection-fairy-lily"),
              spell("Pot of Greed")
            ],
            banished: [mon("Spore", "effect", 400, 800, art: "spore")],
            deck: 25
          ),
          player(5400,
            monsters: [
              nil,
              mon("Jinzo", "effect", 2400, 1500, art: "jinzo"),
              nil,
              mon("Thousand-Eyes Restrict", "fusion", 0, 0,
                pos: "def",
                art: "thousand-eyes-restrict"
              ),
              nil
            ],
            spells: [set("Mirror Force", "trap"), nil, set("Scapegoat", "spell"), nil, nil],
            field: spell("Sogen"),
            grave: [
              mon("Blade Knight", "effect", 1600, 1000, art: "blade-knight"),
              trap("Torrential Tribute"),
              spell("Mystical Space Typhoon")
            ],
            extra: [
              mon("Thousand-Eyes Restrict", "fusion", 0, 0, art: "thousand-eyes-restrict"),
              mon("Thousand-Eyes Restrict", "fusion", 0, 0, art: "thousand-eyes-restrict")
            ],
            deck: 27
          )
        ]
      }
    end

    defp board("edison") do
      %{
        "rule" => "mr1_2",
        "turn" => 4,
        "phase" => "main1",
        "turn_player" => 1,
        "emz" => [nil, nil],
        "players" => [
          player(8000,
            monsters: [
              mon("Spore", "effect", 400, 800, art: "spore"),
              mon("Blade Knight", "effect", 1600, 1000, art: "blade-knight"),
              mon("Elemental HERO The Shining", "effect", 2600, 2100,
                art: "elemental-hero-the-shining"
              ),
              nil,
              nil
            ],
            spells: [
              nil,
              set("Heavy Storm", "spell"),
              set("Mystical Space Typhoon", "spell"),
              nil,
              nil
            ],
            hand: [
              mon("Injection Fairy Lily", "normal", 400, 1500, art: "injection-fairy-lily"),
              mon("Don Zaloog", "effect", 1400, 1500, art: "don-zaloog"),
              spell("Heavy Storm"),
              mon("Chaos Sorcerer", "effect", 2300, 2000, art: "chaos-sorcerer"),
              trap("Bottomless Trap Hole")
            ],
            grave: [
              mon("Injection Fairy Lily", "normal", 400, 1500, art: "injection-fairy-lily"),
              mon("Don Zaloog", "effect", 1400, 1500, art: "don-zaloog"),
              mon("Chaos Sorcerer", "effect", 2300, 2000, art: "chaos-sorcerer")
            ],
            extra:
              for(
                _ <- 1..5,
                do: mon("Thousand-Eyes Restrict", "fusion", 0, 0, art: "thousand-eyes-restrict")
              ),
            deck: 19
          ),
          player(5400,
            monsters: [
              nil,
              mon("Master Hyperion", "effect", 2700, 2100, pos: "def", art: "master-hyperion"),
              nil,
              mon("Gachi Gachi Gantetsu", "effect", 1400, 800,
                art: "gachi-gachi-gantetsu",
                counters: 3
              ),
              mon("Substitoad", "effect", 1300, 1200, pos: "set", art: "substitoad")
            ],
            spells: [set("Mirror Force", "trap"), set("Mirror Force", "trap"), nil, nil, nil],
            field: spell("Sogen"),
            hand: [mon("Gigantes", "effect", 1500, 1500, art: "gigantes")],
            grave: [
              mon("Gyaku-Gire Panda", "effect", 400, 1600, art: "gyaku-gire-panda"),
              mon("Goblin Attack Force", "effect", 2300, 0, art: "goblin-attack-force"),
              trap("Call of the Haunted"),
              spell("Brain Control")
            ],
            banished: [mon("Treeborn Frog", "effect", 100, 100, art: "treeborn-frog")],
            extra: for(_ <- 1..3, do: mon("Thousand-Eyes Restrict", "fusion", 0, 0)),
            deck: 21
          )
        ]
      }
    end

    defp board("pendulum") do
      %{
        "rule" => "mr3",
        "turn" => 5,
        "phase" => "battle",
        "turn_player" => 2,
        "emz" => [nil, nil],
        "players" => [
          player(7300,
            monsters: [
              mon("Blackwing - Bora the Spear", "effect", 1700, 800,
                art: "blackwing-bora-the-spear"
              ),
              nil,
              mon("Blackwing - Kalut the Moon Shadow", "effect", 1400, 1800,
                art: "blackwing-kalut-the-moon-shadow"
              ),
              mon("Blackwing - Armor Master", "synchro", 2500, 1500,
                art: "blackwing-armor-master"
              ),
              nil
            ],
            spells: [
              card("Stargazer Magician", "pendulum", atk: 1200, def: 2400, scale: true),
              nil,
              set("Dark Hole", "spell"),
              nil,
              card("Timegazer Magician", "pendulum", atk: 1200, def: 2400, scale: true)
            ],
            grave: [
              mon("Blackwing - Vayu the Emblem of Honor", "synchro", 2300, 1500,
                art: "blackwing-vayu-the-emblem-of-honor"
              )
            ],
            extra: [
              mon("Blackwing - Armor Master", "synchro", 2500, 1500,
                art: "blackwing-armor-master"
              )
            ],
            deck: 30
          ),
          player(4200,
            monsters: [
              mon("Gladiator Beast Gyzarus", "effect", 2400, 1500, art: "gladiator-beast-gyzarus"),
              mon("Gladiator Beast Laquari", "effect", 1800, 400,
                pos: "def",
                art: "gladiator-beast-laquari"
              ),
              mon("Gladiator Beast Bestiari", "effect", 1500, 1600,
                art: "gladiator-beast-bestiari"
              ),
              nil,
              mon("Treeborn Frog", "effect", 100, 100, pos: "set")
            ],
            spells: [
              card("Soul Charge", "pendulum", atk: 1500, def: 1300, scale: true),
              nil,
              nil,
              nil,
              card("Wisdom-Eye Magician", "pendulum", atk: 1500, def: 1000, scale: true)
            ],
            field: spell("Mountain"),
            deck: 28
          )
        ]
      }
    end

    defp board("modern") do
      %{
        "rule" => "mr4",
        "turn" => 2,
        "phase" => "main2",
        "turn_player" => 2,
        "emz" => [
          card("Decode Talker", "link", atk: 2300),
          card("Number 39: Utopia", "xyz", atk: 2500, def: 2000, overlay: 2)
        ],
        "players" => [
          player(8000,
            monsters: [
              nil,
              mon("Scrap Dragon", "synchro", 2800, 2000, art: "scrap-dragon"),
              nil,
              mon("Thunder Dragon", "effect", 1600, 1500, pos: "def", art: "thunder-dragon"),
              mon("Wulf, Lightsworn Beast", "effect", 2100, 300, art: "wulf-lightsworn-beast")
            ],
            spells: [nil, set("Called by the Grave", "spell"), nil, nil, nil],
            hand: [spell("Pot of Prosperity"), trap("Solemn Strike")],
            grave:
              for(_ <- 1..12, do: mon("Scrap Beast", "effect", 1600, 1600, art: "scrap-beast")),
            banished: [spell("Lightning Storm")],
            extra: [card("Number 39: Utopia", "xyz", atk: 2500, def: 2000)],
            deck: 31
          ),
          player(6400,
            monsters: [
              mon("Trishula, Dragon of the Ice Barrier", "synchro", 2700, 2000,
                art: "trishula-dragon-of-the-ice-barrier"
              ),
              nil,
              mon("Fabled Kushano", "effect", 1000, 1200, art: "fabled-kushano", overlay: 1),
              nil,
              mon("Dekoichi the Battlechanted Locomotive", "effect", 2500, 1800,
                art: "dekoichi-the-battlechanted-locomotive"
              )
            ],
            spells: [
              nil,
              card("Magical Citadel of Endymion", "spell", counters: 4),
              nil,
              set("Mirror Force", "trap"),
              nil
            ],
            field: spell("Forest"),
            grave: [mon("Tsukuyomi", "effect", 1100, 1400, art: "tsukuyomi")],
            deck: 26
          )
        ]
      }
    end

    defp board("empty") do
      %{
        "rule" => "mr1_2",
        "turn" => nil,
        "phase" => nil,
        "turn_player" => nil,
        "emz" => [nil, nil],
        "players" => [
          player(8000,
            monsters: [nil, nil, mon("Jinzo", "effect", 2400, 1500, art: "jinzo"), nil, nil],
            deck: 40
          ),
          player(0, monsters: [nil, nil, nil, nil, nil], deck: 0)
        ]
      }
    end
  end
end
