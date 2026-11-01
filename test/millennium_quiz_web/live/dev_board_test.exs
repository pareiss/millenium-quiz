defmodule MillenniumQuizWeb.DevBoardTest do
  @moduledoc "The dev preview of the board view (`/dev/board`) and its fixture boards."
  use MillenniumQuizWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @boards ~w(goat edison pendulum modern empty)

  test "every fixture board renders in an open dialog", %{conn: conn} do
    for board <- @boards do
      {:ok, view, html} = live(conn, ~p"/dev/board?board=#{board}")
      assert has_element?(view, "#board-dialog[role=dialog]")
      assert has_element?(view, "#board-button")
      assert html =~ "Mika"
      assert html =~ "Tobias"
    end
  end

  test "an unknown board falls back to the Goat board", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dev/board?board=nope")
    assert has_element?(view, "#fixture-goat.btn-primary")
    assert has_element?(view, "#tile-p2-monsters-1[aria-label*=Jinzo]")
  end

  test "Extra Monster Zones only on the modern board, hands only where the fixture has them", %{
    conn: conn
  } do
    for {board, emz?, hand?} <- [
          {"goat", false, false},
          {"edison", false, true},
          {"pendulum", false, false},
          {"modern", true, true},
          {"empty", false, false}
        ] do
      {:ok, view, _html} = live(conn, ~p"/dev/board?board=#{board}")
      assert has_element?(view, "#board-dialog-emz") == emz?, board
      assert has_element?(view, ".duel-hand") == hand?, board
    end
  end

  test "the modern board has Xyz overlay units and counters, the Pendulum board has scales", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/dev/board?board=modern")
    assert has_element?(view, "[data-badge=overlay]")
    assert has_element?(view, "[data-badge=counters]")

    {:ok, view, _} = live(conn, ~p"/dev/board?board=pendulum")
    assert has_element?(view, "[data-badge=scale]")
  end

  test "a tapped tile is selected and shows in the panel, a second tap clears it", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/dev/board?board=goat")
    refute has_element?(view, "#board-detail")

    view |> element("#tile-p2-monsters-1") |> render_click()
    assert has_element?(view, "#tile-p2-monsters-1[data-selected=true]")
    assert render(view) =~ "board-detail"
    assert has_element?(view, "#board-detail", "Jinzo")

    view |> element("#tile-p2-monsters-1") |> render_click()
    refute has_element?(view, "#board-detail")
  end

  test "a list item selects the card too", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/dev/board?board=edison")
    view |> element("#board-dialog-sheet-1-grave-card-0") |> render_click()
    assert has_element?(view, "#board-detail", "Injection Fairy Lily")
  end

  test "closing the dialog and opening it again with the Board button", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/dev/board?board=goat")
    view |> element("#board-dialog-close") |> render_click()
    refute has_element?(view, "#board-dialog")
    view |> element("#board-button") |> render_click()
    assert has_element?(view, "#board-dialog")
  end

  test "?open=0 keeps the dialog closed", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/dev/board?board=goat&open=0")
    refute has_element?(view, "#board-dialog")
    assert has_element?(view, "#board-button")
  end

  test "the fixtures keep to the data contract", %{conn: conn} do
    for board <- @boards do
      {:ok, view, _} = live(conn, ~p"/dev/board?board=#{board}")
      %{board: b} = :sys.get_state(view.pid).socket.assigns

      assert b["rule"] in ["mr1_2", "mr3", "mr4"]
      assert [p1, p2] = b["players"]
      assert length(b["emz"]) == 2

      for p <- [p1, p2] do
        assert length(p["monsters"]) == 5
        assert length(p["spells"]) == 5
        assert is_integer(p["lp"]) and is_integer(p["deck"])

        cards =
          p["monsters"] ++
            p["spells"] ++
            [p["field"]] ++ p["hand"] ++ p["grave"] ++ p["banished"] ++ p["extra"]

        for c <- Enum.reject(cards, &is_nil/1) do
          assert c["kind"] in ~w(normal effect fusion ritual synchro xyz link pendulum spell trap)
          assert c["pos"] in ~w(atk def set)
          assert is_integer(c["overlay"]) and is_integer(c["counters"])
          assert is_boolean(c["scale"])

          if c["art"] do
            assert File.exists?(Path.join("priv/static", c["art"])), c["art"]
          end
        end
      end
    end
  end
end
