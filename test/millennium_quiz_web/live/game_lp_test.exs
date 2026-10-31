defmodule MillenniumQuizWeb.GameLpTest do
  @moduledoc "The life-point duel as the players see it, from the new-game page to the final panel."
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.Games
  alias MillenniumQuiz.Games.GameRecord

  # Question indexes of playable_format_fixture(6): topic 0 has 0..5 and topic 1
  # has 6..11, from 100 damage up to 3000 (index 5 and 11).
  @hit_3000 5
  @hit_3000_b 11
  @hit_2500 4
  @hit_1600 3

  setup do
    %{format: playable_format_fixture(6)}
  end

  defp create(format, names, opts) do
    {:ok, id} = Games.create_game(format.id, names, [shuffle: & &1] ++ opts)
    id
  end

  # Every player in turn picks the choice given (0 is right, 1 is wrong).
  defp pick(view, choices) do
    for choice <- choices, do: view |> element("#choice-#{choice}") |> render_click()
    view
  end

  describe "new game page" do
    test "the Life Points choice defaults to 4000 and 8000 starts a stronger duel",
         %{conn: conn, format: format} do
      {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play")

      assert has_element?(view, "#lp-choice-4000 input[type=radio][name=start_lp]:checked")
      refute has_element?(view, "#lp-choice-8000 input:checked")

      view
      |> form("#players-form", %{"names" => ["Ann", "Bob"], "start_lp" => "8000"})
      |> render_change()

      assert has_element?(view, "#lp-choice-8000 input:checked")

      assert {:error, {:live_redirect, %{to: "/games/" <> id}}} =
               view
               |> form("#players-form", %{"names" => ["Ann", "Bob"], "start_lp" => "8000"})
               |> render_submit()

      assert {:ok, %{game: %{start_lp: 8000}}} = Games.fetch_game(id)

      {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play")

      assert {:error, {:live_redirect, %{to: "/games/" <> id}}} =
               view |> form("#players-form", %{"names" => ["Ann", "Bob"]}) |> render_submit()

      assert {:ok, %{game: %{start_lp: 4000}}} = Games.fetch_game(id)
    end

    test "a forged value is refused with a message and starts nothing",
         %{conn: conn, format: format} do
      {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play")
      before = MillenniumQuiz.Repo.aggregate(GameRecord, :count)

      for forged <- ["9999", "0", "-4000", "abc", "", ["4000"], %{"x" => "1"}, 4000.5] do
        render_hook(view, "start", %{"names" => ["Ann", "Bob"], "start_lp" => forged})
        assert has_element?(view, "#players-error", "4000 or 8000")
      end

      assert MillenniumQuiz.Repo.aggregate(GameRecord, :count) == before
      # the choice made so far is untouched by forged values
      assert has_element?(view, "#lp-choice-4000 input:checked")
    end

    test "the choice survives a validation error and arrives with Play again",
         %{conn: conn, format: format} do
      {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play")

      view
      |> form("#players-form", %{"names" => ["Ann", "ann"], "start_lp" => "8000"})
      |> render_submit()

      assert has_element?(view, "#players-error")
      assert has_element?(view, "#lp-choice-8000 input:checked")

      # a forged change keeps the choice
      render_hook(view, "change", %{"names" => ["Ann", "Bob"], "start_lp" => "123"})
      assert has_element?(view, "#lp-choice-8000 input:checked")

      {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play?start_lp=8000")
      assert has_element?(view, "#lp-choice-8000 input:checked")

      {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play?start_lp=nope")
      assert has_element?(view, "#lp-choice-4000 input:checked")
    end
  end

  describe "duel in Heart of the Cards" do
    test "a wrong answer costs the damage, a right one nothing, a K.O. ends the duel",
         %{conn: conn, format: format} do
      id = create(format, ["Ann", "Bob"], mode: :free)
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")

      assert has_element?(view, "#lp-0", "4000")
      assert has_element?(view, "#lp-bar-0[role=progressbar][aria-valuenow='4000']")
      assert has_element?(view, "#lp-bar-0 div[style*='width: 100%']")
      assert has_element?(view, "button#question-#{@hit_3000}", "3000")

      view |> element("#question-#{@hit_3000}") |> render_click()
      pick(view, [0, 1])

      assert has_element?(view, "#question-points", "3000 ATK")
      assert has_element?(view, "#damage-result-0", "No damage")
      assert has_element?(view, "#damage-result-1", "Direct hit! 4000 - 3000 = 1000 LP")
      refute has_element?(view, "#all-wrong")
      view |> element("#next-round") |> render_click()

      assert has_element?(view, "#lp-0", "4000")
      assert has_element?(view, "#lp-1", "1000")
      assert has_element?(view, "#lp-bar-1 div[style*='width: 25%']")
      refute has_element?(view, "#eliminated-1")
      # the chooser rotates to Bob
      assert has_element?(view, "#current-player", "Bob")

      view |> element("#question-#{@hit_2500}") |> render_click()
      pick(view, [1, 0])

      assert has_element?(view, "#damage-result-0", "No damage")
      assert has_element?(view, "#damage-result-1", "K.O.")
      # Bob had 1000 LP before the 2500 hit: the row says what he really lost
      assert has_element?(view, "#damage-result-1", "1000 LP, 2500 damage")
      assert has_element?(view, "#result-1", "-1000")
      assert has_element?(view, "#eliminated-1")
      assert has_element?(view, "#next-round", "Show final results")
      view |> element("#next-round") |> render_click()

      assert has_element?(view, "#final")
      assert has_element?(view, "#winner", "Ann wins!")
      assert has_element?(view, "#final-standings li:nth-child(1)#final-player-0", "4000 LP")
      assert has_element?(view, "#final-standings li:nth-child(2)#final-player-1")
      assert has_element?(view, "#final-eliminated-1", "Eliminated")
      refute has_element?(view, "#final-lp-1")
      assert has_element?(view, "#play-again[href*='start_lp=4000']")
    end

    test "when nobody is right everyone is hit", %{conn: conn, format: format} do
      id = create(format, ["Ann", "Bob"], mode: :free, start_lp: 8000)
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")
      assert has_element?(view, "#lp-1", "8000")

      view |> element("#question-#{@hit_1600}") |> render_click()
      pick(view, [1, 2])

      assert has_element?(view, "#all-wrong")
      assert has_element?(view, "#damage-result-0", "8000 - 1600 = 6400 LP")
      assert has_element?(view, "#damage-result-1", "8000 - 1600 = 6400 LP")
      view |> element("#next-round") |> render_click()

      assert has_element?(view, "#lp-0", "6400")
      assert has_element?(view, "#lp-1", "6400")
      assert has_element?(view, "#lp-bar-0 div[style*='width: 80%']")
    end

    test "the last two players dropping to 0 together is a draw", %{conn: conn, format: format} do
      id = create(format, ["Ann", "Bob"], mode: :free)
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")

      view |> element("#question-#{@hit_3000}") |> render_click()
      pick(view, [1, 1])
      view |> element("#next-round") |> render_click()

      view |> element("#question-#{@hit_3000_b}") |> render_click()
      pick(view, [1, 1])
      assert has_element?(view, "#damage-result-0", "K.O.")
      assert has_element?(view, "#damage-result-1", "K.O.")
      view |> element("#next-round") |> render_click()

      assert has_element?(view, "#winner", "Draw: Ann & Bob")
      assert has_element?(view, "#final-standings li:nth-child(1)#final-player-0")
      assert has_element?(view, "#final-eliminated-0")
      assert has_element?(view, "#final-eliminated-1")
    end

    test "an eliminated player is skipped and the duel survives a pause",
         %{conn: conn, format: format} do
      id = create(format, ["Ann", "Bob", "Cy"], mode: :free)
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")

      # Bob and Cy are hit for 3000, then Bob drops out
      view |> element("#question-#{@hit_3000}") |> render_click()
      pick(view, [0, 1, 1])
      view |> element("#next-round") |> render_click()

      view |> element("#question-#{@hit_2500}") |> render_click()
      assert has_element?(view, "#current-player", "Bob")
      pick(view, [1, 0, 0])
      assert has_element?(view, "#damage-result-1", "K.O.")
      assert has_element?(view, "#damage-result-0", "No damage")
      assert has_element?(view, "#damage-result-2", "No damage")
      view |> element("#next-round") |> render_click()

      # Bob is marked on the board and never the chooser; Cy is next
      assert has_element?(view, "#score-1[data-eliminated=true] #eliminated-1", "Eliminated")
      assert has_element?(view, "#score-0[data-eliminated=false]")
      refute has_element?(view, "#eliminated-0")
      assert has_element?(view, "#lp-1", "0")
      assert has_element?(view, "#current-player", "Cy")

      # paused and continued on another device: the same duel
      view |> element("#pause-game") |> render_click()
      assert has_element?(view, "#paused")
      {:ok, other, _html} = live(build_conn(), ~p"/games/#{id}")
      other |> element("#resume-game") |> render_click()
      assert has_element?(other, "#current-player", "Cy")
      assert has_element?(other, "#score-1[data-eliminated=true] #eliminated-1")
      assert has_element?(other, "#lp-0", "4000")
      assert has_element?(other, "#lp-2", "1000")

      # only Cy and Ann answer
      other |> element("#question-#{@hit_1600}") |> render_click()
      assert has_element?(other, "#answer-progress", "1/2")
      pick(other, [1, 0])
      refute has_element?(other, "#result-1")
      assert has_element?(other, "#damage-result-2", "K.O.")
      other |> element("#next-round") |> render_click()

      assert has_element?(other, "#winner", "Ann wins!")
      # the later K.O. ranks above the earlier one
      assert has_element?(other, "#final-standings li:nth-child(1)#final-player-0")
      assert has_element?(other, "#final-standings li:nth-child(2)#final-player-2")
      assert has_element?(other, "#final-standings li:nth-child(3)#final-player-1")
    end

    test "ending early ranks by life points and says so", %{conn: conn, format: format} do
      id = create(format, ["Ann", "Bob"], mode: :free)
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")

      view |> element("#question-#{@hit_1600}") |> render_click()
      pick(view, [1, 0])
      view |> element("#next-round") |> render_click()

      view |> element("#end-game") |> render_click()
      assert has_element?(view, "#end-game-modal", "life points")
      view |> element("#confirm-end") |> render_click()

      assert has_element?(view, "#winner", "Bob wins!")
      assert has_element?(view, "#final-standings li:nth-child(1)#final-player-1", "4000 LP")
      assert has_element?(view, "#final-lp-0", "2400 LP")
    end
  end

  describe "duel in Level Up!" do
    test "topic buttons show the next damage and the duel runs to the end",
         %{conn: conn} do
      format = playable_format_fixture(2)
      id = create(format, ["Ann", "Bob"], mode: :ascending, start_lp: 8000)
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")

      assert has_element?(view, "#topic-0 #next-atk-0", "Next ATK 100")
      assert has_element?(view, "#topic-1 #next-atk-1", "Next ATK 100")
      assert has_element?(view, "#lp-0", "8000")

      view |> element("#topic-0") |> render_click()
      pick(view, [1, 1])
      view |> element("#next-round") |> render_click()

      assert has_element?(view, "#topic-0 #next-atk-0", "Next ATK 400")
      assert has_element?(view, "#topic-1 #next-atk-1", "Next ATK 100")

      view |> element("#topic-0") |> render_click()
      pick(view, [1, 0])
      view |> element("#next-round") |> render_click()

      # topic 0 is done: no button and no next damage
      refute has_element?(view, "#next-atk-0")
      # the chooser rotated, so Bob answered first and was wrong
      assert has_element?(view, "#lp-0", "7900")
      assert has_element?(view, "#lp-1", "7500")

      view |> element("#topic-1") |> render_click()
      pick(view, [0, 0])
      view |> element("#next-round") |> render_click()
      view |> element("#topic-1") |> render_click()
      pick(view, [0, 0])
      view |> element("#next-round", "Show final results") |> render_click()

      assert has_element?(view, "#winner", "Ann wins!")
      assert has_element?(view, "#final-standings li:nth-child(2)#final-player-1", "7500 LP")
    end

    test "equal life points are a tie, not a draw", %{conn: conn} do
      format = playable_format_fixture(1)
      id = create(format, ["Ann", "Bob"], mode: :ascending)
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")

      view |> element("#topic-0") |> render_click()
      pick(view, [0, 0])
      view |> element("#next-round") |> render_click()
      view |> element("#topic-1") |> render_click()
      pick(view, [0, 0])
      view |> element("#next-round") |> render_click()

      assert has_element?(view, "#winner", "Tie: Ann & Bob")
      assert has_element?(view, "#final-player-0", "4000 LP")
    end
  end
end
