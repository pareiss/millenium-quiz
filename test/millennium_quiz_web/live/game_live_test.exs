defmodule MillenniumQuizWeb.GameLiveTest do
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.QuizFixtures
  import Swoosh.TestAssertions

  alias MillenniumQuiz.{Cards, CardSourcesStub, Games, Quiz}

  # Emails are sent from the LiveView process, not the test process.
  setup :set_swoosh_global

  setup do
    %{format: playable_format_fixture(1)}
  end

  test "home lists playable formats", %{conn: conn, format: format} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#format-#{format.id}")
  end

  test "starting a game validates the players", %{conn: conn, format: format} do
    {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play")

    view |> form("#players-form", %{"names" => ["Ann", "ann"]}) |> render_submit()
    assert has_element?(view, "#players-error")

    view |> element("#add-player") |> render_click()
    view |> element("#add-player") |> render_click()
    assert has_element?(view, "#player-name-3")
    refute has_element?(view, "#add-player")

    assert has_element?(view, "#mode-free input:checked")

    assert {:error, {:live_redirect, %{to: "/games/" <> id}}} =
             view
             |> form("#players-form", %{
               "names" => ["Ann", "Bob", "Cid", "Dee"],
               "mode" => "ascending"
             })
             |> render_submit()

    assert {:ok, %{game: %{mode: :ascending}}} = Games.fetch_game(id)
  end

  test "a full Heart of the Cards game", %{conn: conn, format: format} do
    {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"], mode: :free)
    {:ok, view, _html} = live(conn, ~p"/games/#{id}")

    # one question per topic, both worth 10 points; the second topic first
    assert has_element?(view, "#game-mode", "Heart of the Cards")
    assert has_element?(view, "button#question-0", "10")
    view |> element("#question-1") |> render_click()
    assert has_element?(view, "#answer-progress", "1/2")
    view |> element("#choice-0") |> render_click()
    assert has_element?(view, "#answer-progress", "2/2")
    view |> element("#choice-1") |> render_click()

    assert has_element?(view, "#reveal-choice-0.border-success")
    assert has_element?(view, "#round-results li", "+10")
    assert has_element?(view, "#round-results li", "+0")
    view |> element("#next-round") |> render_click()

    refute has_element?(view, "button#question-1")
    assert has_element?(view, "#question-1", "1/2 right")
    view |> element("#question-0") |> render_click()
    view |> element("#choice-1") |> render_click()
    view |> element("#choice-1") |> render_click()
    refute has_element?(view, "#round-results li", "+10")
    view |> element("#next-round", "Show final results") |> render_click()

    assert has_element?(view, "#final")
    assert has_element?(view, "#final-standings")
    assert has_element?(view, "#play-again[href*='mode=free']")
  end

  test "Level Up! lets players choose a topic", %{conn: conn} do
    format = playable_format_fixture(2)
    {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"], mode: :ascending)
    {:ok, view, _html} = live(conn, ~p"/games/#{id}")

    refute has_element?(view, "button#question-1")
    view |> element("#topic-0") |> render_click()
    assert has_element?(view, "#question-points", "10 pts")
    view |> element("#choice-0") |> render_click()
    view |> element("#choice-0") |> render_click()
    view |> element("#next-round") |> render_click()

    view |> element("#topic-0") |> render_click()
    assert has_element?(view, "#question-points", "20 pts")
  end

  test "pause shows resume options and the game continues in another session",
       %{conn: conn, format: format} do
    {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])
    {:ok, view, _html} = live(conn, ~p"/games/#{id}")
    view |> element("#question-0") |> render_click()

    view |> element("#pause-game") |> render_click()
    assert has_element?(view, "#paused")
    assert has_element?(view, "#resume-url[value$='/games/#{id}']")
    assert has_element?(view, "#resume-qr svg")

    view |> form("#email-form", resume: %{email: "nope"}) |> render_submit()
    assert has_element?(view, "#email-form", "is not a valid email")

    view |> form("#email-form", resume: %{email: "duelist@example.com"}) |> render_submit()
    assert_email_sent(to: [{"", "duelist@example.com"}])

    # "another device": a fresh connection opening the link
    {:ok, other, _html} = live(build_conn(), ~p"/games/#{id}")
    other |> element("#resume-game") |> render_click()
    assert has_element?(other, "#choice-0")

    # the first screen follows via PubSub
    assert has_element?(view, "#choice-0")
    _ = render(view)
  end

  test "ending asks for confirmation in a modal", %{conn: conn, format: format} do
    {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])
    {:ok, view, _html} = live(conn, ~p"/games/#{id}")

    view |> element("#end-game") |> render_click()
    assert has_element?(view, "#end-game-modal")
    view |> element("#cancel-end") |> render_click()
    refute has_element?(view, "#end-game-modal")
    assert has_element?(view, "#board")

    view |> element("#end-game") |> render_click()
    view |> element("#confirm-end") |> render_click()
    refute has_element?(view, "#end-game-modal")
    assert has_element?(view, "#final")
  end

  test "questions show their cards as printed on the format's date", %{conn: conn} do
    CardSourcesStub.stub!()
    {:ok, reborn} = Cards.import(83_764_719)

    format = format_fixture(%{"date" => "2004-06-01"})

    for topic <- format.topics do
      {:ok, _} =
        Quiz.create_question(topic, %{"text" => "Who?", "choices" => choices_params()}, [
          reborn.id
        ])
    end

    {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])
    {:ok, view, _html} = live(conn, ~p"/games/#{id}")
    view |> element("#question-0") |> render_click()

    assert has_element?(view, "#question-card-0", "Monster Reborn")

    assert has_element?(
             view,
             "#question-card-0",
             "Select 1 monster from either you or your opponent's Graveyard"
           )

    assert has_element?(view, "#question-card-0", "As printed in Starter Deck: Yugi Evolution")
    assert has_element?(view, "#question-card-0 img[src='/cards/#{reborn.id}/artwork']")
    assert has_element?(view, "#question-card-0 .mq-card__face[data-frame=spell]")
    assert has_element?(view, "#question-card-0 .mq-card__line", "Spell Card")

    # a tap enlarges the card; Esc and the backdrop close it again
    view |> element("#zoom-card-0") |> render_click()
    assert has_element?(view, "#card-zoom .mq-card--large", "Monster Reborn")
    view |> element("#card-zoom") |> render_keydown(%{"key" => "Escape"})
    refute has_element?(view, "#card-zoom")

    view |> element("#zoom-card-0") |> render_click()
    view |> element("#card-zoom > div[phx-click=close_card]") |> render_click()
    refute has_element?(view, "#card-zoom")

    # the hover texts work on thumbnails: nothing lies over the card
    refute has_element?(view, "#question-card-0 button.absolute")

    # a tap on the text box opens the texts in a readable panel
    view |> element("#question-card-0 .mq-card__texts") |> render_click()
    assert has_element?(view, "#card-text .mq-card-panel__body", "Select 1 monster")
    # a click on the panel goes back to the enlarged card
    view |> element("#card-text article") |> render_click()
    refute has_element?(view, "#card-text")
    assert has_element?(view, "#card-zoom .mq-card--large", "Monster Reborn")

    render_click(view, "read_card", %{"card" => "0"})
    view |> element("#card-text-back") |> render_click()
    assert has_element?(view, "#card-zoom")

    render_click(view, "read_card", %{"card" => "0"})
    view |> element("#card-text-close") |> render_click()
    refute has_element?(view, "#card-text")
    refute has_element?(view, "#card-zoom")

    # it is closed by the next answer, and comes back on the reveal
    view |> element("#zoom-card-0") |> render_click()
    view |> element("#choice-0") |> render_click()
    refute has_element?(view, "#card-zoom")
    view |> element("#choice-0") |> render_click()
    assert has_element?(view, "#reveal #question-card-0")
    view |> element("#zoom-card-0") |> render_click()
    assert has_element?(view, "#card-zoom", "Monster Reborn")

    # the same card in a later format shows the current text
    later = format_fixture(%{"date" => "2020-01-01"})

    for topic <- later.topics do
      {:ok, _} =
        Quiz.create_question(topic, %{"text" => "Who?", "choices" => choices_params()}, [
          reborn.id
        ])
    end

    {:ok, id} = Games.create_game(later.id, ["Ann", "Bob"])
    {:ok, view, _html} = live(conn, ~p"/games/#{id}")
    view |> element("#question-0") |> render_click()

    assert has_element?(
             view,
             "#question-card-0",
             "Target 1 monster in either GY; Special Summon it."
           )
  end

  test "unknown games redirect home", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/games/#{Ecto.UUID.generate()}")
  end
end
