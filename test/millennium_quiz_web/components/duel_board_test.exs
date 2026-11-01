defmodule MillenniumQuizWeb.DuelBoardTest do
  use MillenniumQuizWeb.ConnCase, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest
  import MillenniumQuizWeb.DuelComponents

  @css File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

  defp parse(html), do: LazyHTML.from_fragment(html)
  defp q(html, selector), do: html |> parse() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> q(selector) |> Enum.count()
  defp text(html, selector), do: html |> q(selector) |> LazyHTML.text() |> String.trim()
  defp attr(html, selector, name), do: html |> q(selector) |> LazyHTML.attribute(name)

  defp card(name, kind, opts \\ []) do
    %{
      "name" => name,
      "kind" => kind,
      "atk" => opts[:atk],
      "def" => opts[:def],
      "level" => nil,
      "pos" => opts[:pos] || "atk",
      "overlay" => opts[:overlay] || 0,
      "counters" => opts[:counters] || 0,
      "art" => opts[:art],
      "scale" => opts[:scale] || false,
      "password" => 1
    }
  end

  defp side(lp, overrides \\ %{}) do
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
      overrides
    )
  end

  defp board(overrides \\ %{}) do
    Map.merge(
      %{
        "rule" => "mr1_2",
        "turn" => 3,
        "phase" => "main1",
        "turn_player" => 1,
        "emz" => [nil, nil],
        "players" => [side(6200), side(5400)]
      },
      overrides
    )
  end

  defp put_player(board, seat, overrides) do
    update_in(board, ["players", Access.at(seat - 1)], &Map.merge(&1, overrides))
  end

  defp render_board(board, opts \\ []) do
    assigns =
      Map.merge(
        %{
          board: board,
          names: %{1 => "Mika", 2 => "Tobias"},
          on_close: "close",
          on_card: "card"
        },
        Map.new(opts)
      )

    render_component(&duel_board/1, assigns)
  end

  describe "layout by Master Rule" do
    test "the Extra Monster Zones are only there for mr4" do
      emz = [card("Decode Talker", "link", atk: 2300), nil]

      for rule <- ["mr1_2", "mr3"] do
        html = render_board(board(%{"rule" => rule, "emz" => emz}))
        assert count(html, ".duel-emz") == 0
        refute html =~ "Decode Talker"
      end

      html = render_board(board(%{"rule" => "mr4", "emz" => emz}))
      assert count(html, ".duel-emz") == 1
      assert attr(html, ".duel-emz", "aria-label") == ["Extra Monster Zones"]
      # two zones, one with a tile, one empty
      assert count(html, ".duel-emz .duel-cell[data-emz=true]") == 2
      assert count(html, ".duel-emz .duel-cell[data-emz=true][data-empty=true]") == 1
      assert count(html, ".duel-emz .duel-tile-btn") == 1

      assert attr(html, ".duel-emz .duel-tile-btn", "aria-label") == [
               "Decode Talker, attack position, ATK 2300, Extra Monster Zone 1"
             ]
    end

    test "Player 2 is on top, Player 1 at the bottom, five monster and five spell/trap zones each" do
      html = render_board(board())
      assert attr(html, ".duel-side", "data-seat") == ["2", "1"]
      assert text(html, "#board-dialog-side-2 .duel-side-name") =~ "Tobias"
      assert text(html, "#board-dialog-side-1 .duel-side-name") =~ "Mika"
      assert text(html, "#board-dialog-side-2 .duel-side-name small") =~ "Player 2"

      for seat <- [1, 2] do
        assert count(html, "#board-dialog-side-#{seat} [data-row=monsters] .duel-cell") == 5
        assert count(html, "#board-dialog-side-#{seat} [data-row=spells] .duel-cell") == 5
        assert count(html, "#board-dialog-side-#{seat} .duel-cell-field") == 1
      end
    end

    test "the field zone shows a tile with a field spell and the word Field when empty" do
      html = render_board(board() |> put_player(2, %{"field" => card("Sogen", "spell")}))

      assert attr(html, "#board-dialog-side-2 .duel-cell-field .duel-tile-btn", "aria-label") ==
               ["Sogen, Spell card, Player 2 field zone"]

      assert text(html, "#board-dialog-side-1 .duel-cell-field") == "Field"
    end

    test "the hand row is only there for a hand that has cards" do
      html = render_board(board())
      assert count(html, ".duel-hand") == 0

      hand = [card("Heavy Storm", "spell"), card("Jinzo", "effect", atk: 2400, def: 1500)]
      html = render_board(board() |> put_player(1, %{"hand" => hand}))
      assert count(html, "#board-dialog-hand-2") == 0
      assert count(html, "#board-dialog-hand-1") == 1
      assert text(html, "#board-dialog-hand-1 .duel-hand-label") == "Hand · 2"

      assert attr(html, "#board-dialog-hand-1 .duel-tile-btn", "aria-label") == [
               "Heavy Storm, Spell card, Player 1 hand, card 1 of 2",
               "Jinzo, attack position, ATK 2400, Player 1 hand, card 2 of 2"
             ]
    end
  end

  describe "tiles" do
    test "attack position: red strip with a sword before the ATK value, accessible name with zone" do
      html =
        render_board(
          board()
          |> put_player(2, %{
            "monsters" => [nil, card("Jinzo", "effect", atk: 2400, def: 1500), nil, nil, nil]
          })
        )

      assert attr(html, "#tile-p2-monsters-1", "aria-label") == [
               "Jinzo, attack position, ATK 2400, Player 2 monster zone 2"
             ]

      assert attr(html, "#tile-p2-monsters-1 .duel-tile", "data-pos") == ["atk"]
      assert count(html, "#tile-p2-monsters-1 .duel-tile-stat .duel-icon-sword") == 1
      assert count(html, "#tile-p2-monsters-1 .duel-tile-stat .duel-icon-shield") == 0
      assert text(html, "#tile-p2-monsters-1 .duel-tile-stat") == "2400"
      assert attr(html, "#tile-p2-monsters-1", "title") == ["Jinzo"]
    end

    test "defense position: blue strip with a shield before the DEF value, same markup size" do
      html =
        render_board(
          board()
          |> put_player(1, %{
            "monsters" => [
              nil,
              nil,
              card("Master Hyperion", "effect", atk: 2700, def: 2100, pos: "def", art: "/a.jpg"),
              nil,
              nil
            ]
          })
        )

      assert attr(html, "#tile-p1-monsters-2", "aria-label") == [
               "Master Hyperion, defense position, DEF 2100, Player 1 monster zone 3"
             ]

      assert attr(html, "#tile-p1-monsters-2 .duel-tile", "data-pos") == ["def"]
      assert count(html, "#tile-p1-monsters-2 .duel-tile-stat .duel-icon-shield") == 1
      assert count(html, "#tile-p1-monsters-2 .duel-tile-stat .duel-icon-sword") == 0
      assert text(html, "#tile-p1-monsters-2 .duel-tile-stat") == "2100"
      # the artwork is an image the CSS turns a quarter inside the same tile
      assert attr(html, "#tile-p1-monsters-2 .duel-tile-art img", "src") == ["/a.jpg"]
    end

    test "face down: the card back, and neither name nor art nor stats in the markup" do
      html =
        render_board(
          board()
          |> put_player(2, %{
            "monsters" => [
              card("Spore", "effect", atk: 400, def: 800, pos: "set", art: "/s.jpg"),
              nil,
              nil,
              nil,
              nil
            ],
            "spells" => [card("Mirror Force", "trap", pos: "set"), nil, nil, nil, nil]
          })
        )

      assert attr(html, "#tile-p2-monsters-0", "aria-label") == [
               "Face-down defense monster, Player 2 monster zone 1"
             ]

      assert attr(html, "#tile-p2-spells-0", "aria-label") == [
               "Face-down spell or trap card, Player 2 spell/trap zone 1"
             ]

      for id <- ["#tile-p2-monsters-0", "#tile-p2-spells-0"] do
        assert attr(html, "#{id} .duel-tile", "data-pos") == ["set"]
        assert count(html, "#{id} img") == 0
        assert count(html, "#{id} .duel-tile-name") == 0
        assert count(html, "#{id} .duel-tile-stat") == 0
        assert attr(html, id, "title") == []
      end

      refute html =~ "Spore"
      refute html =~ "Mirror Force"
      assert attr(html, "#tile-p2-monsters-0 .duel-tile", "data-monster") == ["true"]
      assert attr(html, "#tile-p2-spells-0 .duel-tile", "data-monster") == ["false"]
    end

    test "frame colour is by kind, a spell or trap has no strip" do
      html =
        render_board(
          board()
          |> put_player(1, %{
            "monsters" => [
              card("A", "fusion", atk: 1, def: 1),
              card("B", "xyz", atk: 1, def: 1),
              card("C", "link", atk: 1),
              card("D", "pendulum", atk: 1, def: 1),
              card("E", "ritual", atk: 1, def: 1)
            ],
            "spells" => [
              card("Heavy Storm", "spell"),
              card("Mirror Force", "trap"),
              nil,
              nil,
              nil
            ]
          })
        )

      kinds = attr(html, "#board-dialog-side-1 [data-row=monsters] .duel-tile", "data-kind")
      assert kinds == ["fusion", "xyz", "link", "pendulum", "ritual"]

      assert attr(html, "#board-dialog-side-1 [data-row=spells] .duel-tile", "data-kind") == [
               "spell",
               "trap"
             ]

      assert count(html, "#board-dialog-side-1 [data-row=spells] .duel-tile-stat") == 0
      # a link monster has no DEF: an attack tile with a ?-free ATK
      assert text(html, "#tile-p1-monsters-2 .duel-tile-stat") == "1"
    end

    test "overlay units, counters and a Pendulum scale are badges and part of the name" do
      html =
        render_board(
          board()
          |> put_player(1, %{
            "monsters" => [
              nil,
              card("Utopia", "xyz", atk: 2500, def: 2000, overlay: 2),
              nil,
              nil,
              nil
            ],
            "spells" => [
              card("Stargazer Magician", "pendulum", scale: true, counters: 3),
              nil,
              nil,
              nil,
              nil
            ]
          })
        )

      assert count(html, "#tile-p1-monsters-1 [data-badge=overlay]") == 1
      assert text(html, "#tile-p1-monsters-1 [data-badge=overlay]") =~ "×2"
      assert [label] = attr(html, "#tile-p1-monsters-1", "aria-label")
      assert label =~ "2 overlay units"

      assert count(html, "#tile-p1-spells-0 [data-badge=scale]") == 1
      assert count(html, "#tile-p1-spells-0 [data-badge=counters]") == 1
      assert [label] = attr(html, "#tile-p1-spells-0", "aria-label")
      assert label =~ "Pendulum Scale"
      assert label =~ "3 counters"
      assert label =~ "Player 1 Pendulum zone 1"
    end

    test "artwork is an image when the card has one, an initial when not" do
      html =
        render_board(
          board()
          |> put_player(1, %{
            "monsters" => [
              card("Jinzo", "effect", atk: 1, def: 1, art: "/images/avatars/jinzo.jpg"),
              card("zaborg", "effect", atk: 1, def: 1),
              nil,
              nil,
              nil
            ]
          })
        )

      assert attr(html, "#tile-p1-monsters-0 img", "src") == ["/images/avatars/jinzo.jpg"]
      assert attr(html, "#tile-p1-monsters-0 img", "alt") == [""]
      assert count(html, "#tile-p1-monsters-1 img") == 0
      assert text(html, "#tile-p1-monsters-1 .duel-tile-initial") == "Z"
    end

    test "a tap sends on_card with the key, player, zone and index; the selected tile is marked" do
      board =
        board()
        |> put_player(2, %{
          "monsters" => [nil, nil, card("Jinzo", "effect", atk: 1, def: 1), nil, nil]
        })

      html = render_board(board, selected: "p2:monsters:2")
      assert attr(html, "#tile-p2-monsters-2", "phx-click") == ["card"]
      assert attr(html, "#tile-p2-monsters-2", "phx-value-key") == ["p2:monsters:2"]
      assert attr(html, "#tile-p2-monsters-2", "phx-value-player") == ["2"]
      assert attr(html, "#tile-p2-monsters-2", "phx-value-zone") == ["monsters"]
      assert attr(html, "#tile-p2-monsters-2", "phx-value-index") == ["2"]
      assert attr(html, "#tile-p2-monsters-2", "data-selected") == ["true"]
      assert attr(html, "#tile-p2-monsters-2", "aria-current") == ["true"]
      assert count(html, "[data-selected=true]") == 1
    end
  end

  describe "life points and the turn" do
    test "names, LP numbers, bars and the subtitle" do
      html = render_board(board())
      assert text(html, "#board-dialog-lp-2") == "5400"
      assert text(html, "#board-dialog-lp-1") == "6200"

      assert attr(html, "#board-dialog-side-1 [role=progressbar]", "aria-label") == [
               "Mika's life points"
             ]

      assert attr(html, "#board-dialog-side-1 [role=progressbar]", "aria-valuenow") == ["6200"]
      assert attr(html, "#board-dialog-side-1 [role=progressbar]", "aria-valuemax") == ["8000"]
      assert text(html, ".duel-board-title span") == "Turn 3 · Main Phase 1 · Mika to move"
      assert attr(html, "#board-dialog-side-1", "aria-current") == ["true"]
      assert attr(html, "#board-dialog-side-2", "aria-current") == []
    end

    test "no turn information: no subtitle; 0 LP is an empty bar" do
      html =
        render_board(
          board(%{"turn" => nil, "phase" => nil, "turn_player" => nil})
          |> put_player(2, %{"lp" => 0})
        )

      assert count(html, ".duel-board-title span") == 0
      assert count(html, "#board-dialog-side-2 .duel-lp-bar u.off") == 10
    end
  end

  describe "chips and the lists" do
    setup do
      grave = [card("Spore", "effect", atk: 400, def: 800), card("Pot of Greed", "spell")]

      board =
        board()
        |> put_player(1, %{"grave" => grave, "deck" => 25, "extra" => []})
        |> put_player(2, %{
          "banished" => [card("Jinzo", "effect", atk: 2400, def: 1500)],
          "deck" => 0
        })

      %{html: render_board(board)}
    end

    test "a chip with cards opens its list, a chip at 0 is dimmed and inert", %{html: html} do
      assert attr(html, "#board-dialog-chip-1-grave", "disabled") == []
      assert [click] = attr(html, "#board-dialog-chip-1-grave", "phx-click")
      assert click =~ "board-dialog-sheet-1-grave"
      assert attr(html, "#board-dialog-chip-1-grave", "aria-label") == ["Player 1 Grave, 2 cards"]
      assert attr(html, "#board-dialog-chip-1-grave", "data-zero") == ["false"]
      assert text(html, "#board-dialog-chip-1-grave") =~ "2"

      for id <- [
            "#board-dialog-chip-1-extra",
            "#board-dialog-chip-1-banished",
            "#board-dialog-chip-2-grave"
          ] do
        assert attr(html, id, "disabled") == [""]
        assert attr(html, id, "phx-click") == []
        assert attr(html, id, "data-zero") == ["true"]
      end

      assert attr(html, "#board-dialog-chip-1-extra", "aria-label") == ["Player 1 Extra, 0 cards"]

      assert attr(html, "#board-dialog-chip-2-banished", "aria-label") == [
               "Player 2 Banish, 1 card"
             ]
    end

    test "the Deck chip only shows a count and is not a button", %{html: html} do
      assert count(html, "#board-dialog-chip-1-deck") == 1
      assert count(html, "button#board-dialog-chip-1-deck") == 0
      assert text(html, "#board-dialog-chip-1-deck") =~ "25"
      assert attr(html, "#board-dialog-chip-1-deck", "aria-label") == ["Player 1 Deck, 25 cards"]
      assert attr(html, "#board-dialog-chip-2-deck", "data-zero") == ["true"]
    end

    test "a list sheet exists only for a stack with cards, with a list item per card", %{
      html: html
    } do
      assert count(html, ".duel-sheet") == 2
      assert count(html, "#board-dialog-sheet-1-grave") == 1
      assert count(html, "#board-dialog-sheet-2-banished") == 1
      assert count(html, "#board-dialog-sheet-1-extra") == 0
      assert attr(html, "#board-dialog-sheet-1-grave", "role") == ["dialog"]
      assert attr(html, "#board-dialog-sheet-1-grave", "aria-label") == ["Mika · Graveyard (2)"]
      assert count(html, "#board-dialog-sheet-1-grave .duel-list-item") == 2

      assert attr(html, "#board-dialog-sheet-1-grave .duel-list-item", "aria-label") == [
               "Spore, ATK 400, DEF 800, Player 1 graveyard",
               "Pot of Greed, Player 1 graveyard"
             ]

      assert attr(html, "#board-dialog-sheet-1-grave .duel-list-item", "phx-value-key") == [
               "p1:grave:0",
               "p1:grave:1"
             ]

      # the sheets are not inside the mat's container (a container holds fixed children)
      assert count(html, ".duel-board-main .duel-sheet") == 0
      assert text(html, "#board-dialog-sheet-1-grave .duel-list-name") =~ "Spore"
    end
  end

  describe "dialog" do
    test "is a modal dialog with a close button and an Escape binding" do
      html = render_board(board())
      assert attr(html, "#board-dialog", "role") == ["dialog"]
      assert attr(html, "#board-dialog", "aria-modal") == ["true"]
      assert attr(html, "#board-dialog", "aria-labelledby") == ["board-dialog-title"]
      assert attr(html, "#board-dialog", "phx-window-keydown") == ["close"]
      assert attr(html, "#board-dialog", "phx-key") == ["escape"]
      assert attr(html, "#board-dialog-close", "phx-click") == ["close"]
      assert attr(html, "#board-dialog-close", "aria-label") == ["Close the board"]
      assert attr(html, ".duel-board-backdrop", "phx-click") == ["close"]
    end

    test "the detail slot fills the panel, a hint shows without one" do
      assert render_board(board()) =~ "Select a card to read it."

      html =
        render_component(
          fn assigns ->
            ~H"""
            <.duel_board board={board()} on_close="close">
              <:detail><b id="picked">Jinzo</b></:detail>
            </.duel_board>
            """
          end,
          %{}
        )

      assert text(html, ".duel-board-panel #picked") == "Jinzo"
      refute html =~ "Select a card to read it."
    end
  end

  describe "board_button" do
    test "shows the turn, the phase and how many cards are on the field" do
      board =
        board()
        |> put_player(1, %{
          "monsters" => [card("Jinzo", "effect", atk: 1, def: 1), nil, nil, nil, nil]
        })
        |> put_player(2, %{
          "spells" => [card("Mirror Force", "trap", pos: "set"), nil, nil, nil, nil],
          "field" => card("Sogen", "spell"),
          "hand" => [card("Heavy Storm", "spell")],
          "grave" => [card("Spore", "effect")]
        })

      html = render_component(&board_button/1, %{board: board, on_click: "open"})
      assert attr(html, "#board-button", "phx-click") == ["open"]
      assert attr(html, "#board-button", "aria-haspopup") == ["dialog"]
      assert text(html, "#board-button") =~ "Board"
      assert count(html, "#board-button .hero-table-cells") == 1
      assert text(html, "#board-button-note") =~ "Turn 3 · Main Phase 1"
      # hand and graveyard cards are not on the field
      assert text(html, "#board-button-note") =~ "3 cards on the field"
    end

    test "singular, an Extra Monster Zone counts only for mr4, no turn: only the cards line" do
      emz = [card("Decode Talker", "link", atk: 2300), nil]
      board = board(%{"turn" => nil, "phase" => nil, "emz" => emz})

      html = render_component(&board_button/1, %{board: board, on_click: "open"})
      assert text(html, "#board-button-note") == "0 cards on the field"

      html =
        render_component(&board_button/1, %{board: %{board | "rule" => "mr4"}, on_click: "open"})

      assert text(html, "#board-button-note") == "1 card on the field"
      assert count(html, "#board-button-note span") == 1
    end
  end

  describe "css" do
    test "tile sizes follow the board's container: 66px, 54px under 360px, 96px from 560px" do
      assert @css =~ "--duel-cap: 4.125rem"
      assert @css =~ "@container duel-board (max-width: 359.98px)"
      assert @css =~ "--duel-cap: 3.375rem"
      assert @css =~ "@container duel-board (min-width: 560px)"
      assert @css =~ "--duel-cap: 6rem"
      assert @css =~ "container: duel-board / inline-size"
    end

    test "no border-image with color-mix and no @apply" do
      board_css = @css |> String.split("The board view (DuelComponents") |> List.last()
      refute board_css =~ "border-image"
      refute board_css =~ "@apply"
    end
  end
end
