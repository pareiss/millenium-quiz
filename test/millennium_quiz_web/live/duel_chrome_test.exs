defmodule MillenniumQuizWeb.DuelChromeTest do
  @moduledoc """
  The player-facing chrome of the duel theme (header, home, new game, suggest pages):
  the ids and hook classes the CSS and the browser checks rely on.
  """
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.QuizFixtures

  setup do
    %{format: playable_format_fixture(1)}
  end

  test "the header carries the duel hooks and the theme toggle", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")

    assert has_element?(view, "#site-header.duel-header")
    assert has_element?(view, "#brand-link .duel-brand-mark")
    assert has_element?(view, "#brand-link .duel-brand-name")
    assert has_element?(view, "#theme-toggle.duel-toggle button[data-phx-theme=system]")
    assert has_element?(view, "#theme-toggle button[data-phx-theme=duel-light]")
    assert has_element?(view, "#theme-toggle button[data-phx-theme=duel-dark]")
  end

  test "the home page: hero, format cards as plates, the suggest bar", %{conn: conn, format: f} do
    {:ok, view, _} = live(conn, ~p"/")

    assert has_element?(view, "h1.duel-hero")
    assert has_element?(view, "#format-#{f.id}.duel-plate.duel-format .duel-tag")
    assert has_element?(view, "#format-#{f.id} .duel-play")
    assert has_element?(view, "#suggest-footer.duel-footer #suggest-link.duel-btn")
  end

  test "the new game page: panel, Synchro ring avatars, option cards", %{conn: conn, format: f} do
    {:ok, view, _} = live(conn, ~p"/formats/#{f.id}/play")

    assert has_element?(view, "#new-game-panel.duel-plate")
    assert has_element?(view, "#avatar-button-0 .duel-ring use[href='#duel-ring']")
    assert has_element?(view, "#avatar-button-1 .duel-ring")
    assert has_element?(view, "#mode-choice .duel-legend")
    assert has_element?(view, "#lp-choice label.duel-option input[type=radio]:checked")
    assert has_element?(view, "#start-game.duel-btn")
    assert has_element?(view, "#add-player.duel-btn")

    # the picker marks the chosen picture with the ring, no other one
    view |> element("#avatar-button-0") |> render_click()
    assert has_element?(view, "#avatar-panel-0.duel-picker")
    assert has_element?(view, "#avatar-panel-0 .duel-picked .duel-picked-ring use")

    ring_count =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(".duel-picked-ring")
      |> Enum.count()

    assert ring_count == 1
  end

  test "the suggest pages are plates too", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/suggest")
    assert has_element?(view, "#suggest-panel.duel-plate.duel-surface")
    assert has_element?(view, "#send-suggestion")

    {:ok, view, _} = live(conn, ~p"/suggest/thanks")
    assert has_element?(view, "#suggest-thanks-panel.duel-plate")
  end
end
