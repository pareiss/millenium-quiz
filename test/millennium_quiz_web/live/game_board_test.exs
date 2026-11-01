defmodule MillenniumQuizWeb.GameBoardTest do
  @moduledoc """
  The board of a question in `GameLive`: the button, the dialog, the card of a
  tapped tile, and games without a board.
  """
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.BoardGameFixtures, only: [board_format_fixture: 0, stored_board: 1]

  alias MillenniumQuiz.Games
  alias MillenniumQuiz.Games.GameRecord
  alias MillenniumQuiz.Repo

  # The first question of the first topic has the board: index 0 of the game.
  defp start(%{format: format}, opts \\ []) do
    {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"], opts)
    id
  end

  defp open_question(conn, id) do
    {:ok, _} = Games.choose(id, 0)
    {:ok, view, _html} = live(conn, ~p"/games/#{id}")
    view
  end

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

  defp tap_tile(view, key) do
    view |> element("#board-dialog-tile-#{String.replace(key, ":", "-")}") |> render_click()
  end

  setup do
    board_format_fixture()
  end

  describe "the Board button" do
    test "shows for a question with a board, not while choosing nor on other questions",
         %{conn: conn} = ctx do
      id = start(ctx)
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")
      refute has_element?(view, "#board-button")

      {:ok, _} = Games.choose(id, 1)
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")
      assert has_element?(view, "#question-text")
      refute has_element?(view, "#board-button")
      refute has_element?(view, "#board-layer")

      {:ok, _} = Games.answer(id, 0)
      {:ok, _} = Games.answer(id, 0)
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")
      assert has_element?(view, "#reveal")
      refute has_element?(view, "#board-button")
    end

    test "sits between the question text and the answers", %{conn: conn} = ctx do
      view = open_question(conn, start(ctx))
      assert has_element?(view, "#board-button[aria-haspopup=dialog]")
      assert has_element?(view, "#board-button-note")
      refute has_element?(view, "#board-dialog")

      html = render(view)
      {text, _} = :binary.match(html, ~s(id="question-text"))
      {button, _} = :binary.match(html, ~s(id="board-button"))
      {choice, _} = :binary.match(html, ~s(id="choice-0"))
      assert text < button and button < choice
    end

    test "stays on the reveal screen, as the button only", %{conn: conn} = ctx do
      id = start(ctx)
      view = open_question(conn, id)
      {:ok, _} = Games.answer(id, 0)
      {:ok, _} = Games.answer(id, 1)

      assert has_element?(view, "#reveal")
      assert has_element?(view, "#board-button")
      refute has_element?(view, "#board-dialog")

      view |> element("#board-button") |> render_click()
      assert has_element?(view, "#board-dialog")
    end
  end

  describe "the dialog" do
    test "opens and closes without touching the game", %{conn: conn} = ctx do
      id = start(ctx)
      view = open_question(conn, id)
      {:ok, %{game: before}} = Games.fetch_game(id)
      turn_key = assigns(view).turn_key

      view |> element("#board-button") |> render_click()
      assert has_element?(view, "#board-dialog[role=dialog][aria-modal=true]")
      assert has_element?(view, "#board-dialog-tile-p1-monsters-1")
      assert has_element?(view, "#board-dialog-close")
      # still the same player's turn to answer
      %{name: name} = MillenniumQuiz.Game.current_player(before)
      assert has_element?(view, "#current-player", name)
      assert {:ok, %{game: ^before}} = Games.fetch_game(id)
      assert assigns(view).turn_key == turn_key

      view |> element("#board-dialog-close") |> render_click()
      refute has_element?(view, "#board-dialog")
      assert has_element?(view, "#board-button")
      assert assigns(view).board_open == false
    end

    test "closes with Escape and with the backdrop", %{conn: conn} = ctx do
      view = open_question(conn, start(ctx))

      view |> element("#board-button") |> render_click()
      view |> element("#board-dialog") |> render_keydown(%{"key" => "Escape"})
      refute has_element?(view, "#board-dialog")

      view |> element("#board-button") |> render_click()
      view |> element("#board-dialog > .duel-board-backdrop") |> render_click()
      refute has_element?(view, "#board-dialog")
    end

    test "gives the focus back to the button when it closes", %{conn: conn} = ctx do
      view = open_question(conn, start(ctx))
      view |> element("#board-button") |> render_click()

      for selector <- ["#board-dialog-close", "#board-dialog > .duel-board-backdrop"] do
        html = view |> element(selector) |> render()
        assert html =~ "close_board" and html =~ "focus" and html =~ "#board-button"
      end
    end

    test "labels the players like the markers of the question text", %{conn: conn} = ctx do
      view = open_question(conn, start(ctx))
      view |> element("#board-button") |> render_click()

      assert has_element?(view, "#board-dialog-lp-1", "6200")
      assert has_element?(view, "#board-dialog-lp-2", "5400")
      assert has_element?(view, "#board-dialog .duel-side-name-text", "Player 1")
      assert has_element?(view, "#board-dialog .duel-side-name-text", "Player 2")
      refute has_element?(view, "#board-dialog .duel-side-name-text", "Ann")
    end

    test "stays open while the same question goes on, and closes with the round",
         %{conn: conn} = ctx do
      id = start(ctx)
      view = open_question(conn, id)
      view |> element("#board-button") |> render_click()

      {:ok, _} = Games.answer(id, 0)
      _ = render(view)
      assert has_element?(view, "#board-dialog")

      {:ok, _} = Games.answer(id, 1)
      _ = render(view)
      assert has_element?(view, "#reveal")
      assert has_element?(view, "#board-dialog")

      {:ok, _} = Games.next_round(id)
      _ = render(view)
      refute has_element?(view, "#board-dialog")
      assert assigns(view).board_open == false
    end

    test "closes when the game is paused and is not back after resuming", %{conn: conn} = ctx do
      id = start(ctx)
      view = open_question(conn, id)
      view |> element("#board-button") |> render_click()

      {:ok, _} = Games.pause(id)
      _ = render(view)
      assert has_element?(view, "#paused")
      refute has_element?(view, "#board-dialog")

      {:ok, _} = Games.resume(id)
      _ = render(view)
      assert has_element?(view, "#board-button")
      refute has_element?(view, "#board-dialog")
    end

    test "the end-game dialog stacks above the board", %{conn: conn} = ctx do
      view = open_question(conn, start(ctx))
      view |> element("#board-button") |> render_click()
      render_click(view, "confirm_end", %{})

      html = render(view)
      {board, _} = :binary.match(html, ~s(id="board-dialog"))
      {modal, _} = :binary.match(html, ~s(id="end-game-modal"))
      assert board < modal
    end

    test "cannot be opened when there is nothing to show", %{conn: conn} = ctx do
      id = start(ctx)
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")
      render_click(view, "open_board", %{})
      refute has_element?(view, "#board-dialog")

      {:ok, _} = Games.choose(id, 1)
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")
      render_click(view, "open_board", %{})
      refute has_element?(view, "#board-dialog")
      assert assigns(view).board_open == false
    end
  end

  describe "a tapped card" do
    test "below 900px opens the card dialog above the board", %{conn: conn} = ctx do
      view = open_question(conn, start(ctx))
      view |> element("#board-button") |> render_click()

      tap_tile(view, "p1:monsters:1")
      assert has_element?(view, "#board-card-zoom .mq-card--large", "Board Card 1001")
      assert has_element?(view, "#board-card-zoom a[href='https://yugipedia.com']")
      assert has_element?(view, "#board-dialog")
      refute has_element?(view, "#board-detail")

      # the card dialog comes after the board, so it stacks above
      html = render(view)
      {board, _} = :binary.match(html, ~s(id="board-dialog"))
      {card, _} = :binary.match(html, ~s(id="board-card-zoom"))
      assert board < card

      view |> element("#board-card-zoom") |> render_keydown(%{"key" => "Escape"})
      refute has_element?(view, "#board-card-zoom")
      assert has_element?(view, "#board-dialog")
      assert assigns(view).board_selected == nil
    end

    test "Escape closes the card dialog, not the board behind it", %{conn: conn} = ctx do
      view = open_question(conn, start(ctx))
      view |> element("#board-button") |> render_click()
      tap_tile(view, "p1:monsters:1")

      # the board's own binding does nothing while the card dialog is open
      assert view |> element("#board-dialog") |> render() =~ ~s(phx-window-keydown="[]")
      view |> element("#board-card-zoom-close") |> render_click()
      refute has_element?(view, "#board-card-zoom")
      assert has_element?(view, "#board-dialog")
      refute view |> element("#board-dialog") |> render() =~ ~s(phx-window-keydown="[]")
    end

    test "from 900px fills the side panel and a second tap clears it", %{conn: conn} = ctx do
      view = open_question(conn, start(ctx))
      view |> element("#board-button") |> render_click()
      render_hook(view, "board_layout", %{"wide" => true})

      tap_tile(view, "p1:monsters:1")
      assert has_element?(view, "#board-detail .mq-card", "Board Card 1001")
      assert has_element?(view, "#board-detail a[href='https://yugipedia.com']")
      assert has_element?(view, "#board-dialog-tile-p1-monsters-1[data-selected=true]")
      refute has_element?(view, "#board-card-zoom")

      tap_tile(view, "p2:field:0")
      assert has_element?(view, "#board-detail .mq-card", "Board Card 1007")

      tap_tile(view, "p2:field:0")
      refute has_element?(view, "#board-detail")
    end

    test "turning the device switches between the panel and the dialog", %{conn: conn} = ctx do
      view = open_question(conn, start(ctx))
      view |> element("#board-button") |> render_click()
      render_hook(view, "board_layout", %{"wide" => true})
      tap_tile(view, "p1:hand:0")
      assert has_element?(view, "#board-detail")

      render_hook(view, "board_layout", %{"wide" => false})
      assert has_element?(view, "#board-card-zoom")
      refute has_element?(view, "#board-detail")
    end

    test "reads cards in the lists (graveyard, Extra Deck) too", %{conn: conn} = ctx do
      view = open_question(conn, start(ctx))
      view |> element("#board-button") |> render_click()

      render_click(view, "board_card", %{"key" => "p1:grave:0"})
      assert has_element?(view, "#board-card-zoom", "Board Card 1004")
      view |> element("#board-card-zoom-close") |> render_click()

      render_click(view, "board_card", %{"key" => "p2:extra:0"})
      assert has_element?(view, "#board-card-zoom", "Board Card 1008")
    end

    test "Player 1's face-down card can be read, Player 2's cannot", %{conn: conn} = ctx do
      view = open_question(conn, start(ctx))
      view |> element("#board-button") |> render_click()

      assert has_element?(view, "button#board-dialog-tile-p1-monsters-2")
      assert has_element?(view, "div#board-dialog-tile-p2-monsters-3[data-inert=true]")
      refute has_element?(view, "button#board-dialog-tile-p2-monsters-3")

      # a forged event learns nothing either
      render_click(view, "board_card", %{"key" => "p2:monsters:3"})
      refute has_element?(view, "#board-card-zoom")
      assert assigns(view).board_selected == nil

      tap_tile(view, "p1:monsters:2")
      assert has_element?(view, "#board-card-zoom", "Board Card 1002")
      assert has_element?(view, "#board-card-zoom-close")
    end

    test "a board with reveal_all lets every face-down card be read", %{conn: conn} = ctx do
      ctx.question
      |> Ecto.Changeset.change(board: stored_board(%{"reveal_all" => true}))
      |> Repo.update!()

      view = open_question(conn, start(ctx))
      view |> element("#board-button") |> render_click()

      assert has_element?(view, "button#board-dialog-tile-p2-monsters-3")
      tap_tile(view, "p2:monsters:3")
      assert has_element?(view, "#board-card-zoom", "Board Card 1006")
    end

    test "ignores keys that are not a card of the board", %{conn: conn} = ctx do
      view = open_question(conn, start(ctx))
      view |> element("#board-button") |> render_click()

      for key <- [
            "",
            "nonsense",
            "p3:monsters:0",
            "p0:monsters:0",
            "p1:monsters",
            "p1:monsters:x",
            "p1:monsters:-1",
            "p1:monsters:1.5",
            "p1:monsters:99",
            "p1:monsters:0",
            "p1:deck:0",
            "p1:field:1",
            "p1:hand:3",
            "emz:0",
            "emz:2",
            "p1:grave:1",
            "p1:monsters:1:2"
          ] do
        render_click(view, "board_card", %{"key" => key})
        assert assigns(view).board_selected == nil, inspect(key)
      end

      # wrong types and missing params do not crash the page
      render_click(view, "board_card", %{})
      render_click(view, "board_card", %{"key" => ["p1:monsters:1"]})
      render_hook(view, "board_layout", %{"wide" => "yes"})
      render_hook(view, "board_layout", %{})
      assert has_element?(view, "#board-dialog")
      refute has_element?(view, "#board-card-zoom")
      assert assigns(view).board_wide == false
    end

    test "is ignored while the board is closed", %{conn: conn} = ctx do
      view = open_question(conn, start(ctx))
      render_click(view, "board_card", %{"key" => "p1:monsters:1"})
      assert assigns(view).board_selected == nil
      refute has_element?(view, "#board-card-zoom")
    end
  end

  describe "games without a board" do
    test "a game from before boards has no button", %{conn: conn} = ctx do
      id = start(ctx)
      record = Repo.get!(GameRecord, id)

      old =
        record.state
        |> Map.delete("board_cards")
        |> update_in(["questions"], fn questions ->
          Enum.map(questions, &Map.delete(&1, "board"))
        end)

      record |> Ecto.Changeset.change(state: old) |> Repo.update!()

      view = open_question(conn, id)
      assert has_element?(view, "#question-text")
      refute has_element?(view, "#board-button")
      refute has_element?(view, "#board-layer")
      render_click(view, "open_board", %{})
      refute has_element?(view, "#board-dialog")
    end

    test "games of 4000 and 8000 life points play on as before", %{conn: conn} = ctx do
      for lp <- [4000, 8000] do
        {:ok, id} = Games.create_game(ctx.format.id, ["Ann", "Bob"], start_lp: lp)
        {:ok, _} = Games.choose(id, 3)
        {:ok, view, _html} = live(conn, ~p"/games/#{id}")

        refute has_element?(view, "#board-button")
        assert has_element?(view, "#question-text")
        assert has_element?(view, "#choice-0")
        view |> element("#choice-0") |> render_click()
        view |> element("#choice-1") |> render_click()
        assert has_element?(view, "#reveal")
        refute has_element?(view, "#board-button")

        # the second player to answer was wrong on the second question of a topic: 400
        assert {:ok, %{game: %{start_lp: ^lp, players: players}}} = Games.fetch_game(id)
        assert players |> Enum.map(& &1.lp) |> Enum.sort() == [lp - 400, lp]
      end
    end
  end
end
