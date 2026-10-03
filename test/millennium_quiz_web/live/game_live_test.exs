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

    # phone keyboards: names are not autocorrected, Enter says "next"
    assert has_element?(
             view,
             "#player-name-0[autocapitalize=words][autocorrect=off][spellcheck=false][enterkeyhint=next]"
           )

    assert has_element?(view, "#players-form[phx-hook$=NextOnEnter]")

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
    assert has_element?(view, "#question-card-0 img[draggable=false]")
    assert has_element?(view, "#game[data-turn-key]")
    assert has_element?(view, "#choice-0.mq-nosel")
    assert has_element?(view, "#question-card-0 .mq-card__face[data-frame=spell]")
    assert has_element?(view, "#question-card-0 .mq-card__line", "Spell Card")

    # a tap enlarges the card; Esc and the backdrop close it again
    view |> element("#zoom-card-0") |> render_click()
    assert has_element?(view, "#card-zoom .mq-card--large", "Monster Reborn")
    # the Yugipedia credit is shown with the enlarged text
    assert has_element?(view, "#card-zoom a[href='https://yugipedia.com']")
    # the Esc hint is for keyboards only (hidden without hover)
    assert has_element?(view, "#card-zoom-hint .hidden", "press Esc")
    view |> element("#card-zoom") |> render_keydown(%{"key" => "Escape"})
    refute has_element?(view, "#card-zoom")

    view |> element("#zoom-card-0") |> render_click()
    view |> element("#card-zoom > div[phx-click=close_card]") |> render_click()
    refute has_element?(view, "#card-zoom")

    # a card that the question doesn't have can't be enlarged
    render_click(view, "zoom_card", %{"card" => "5"})
    render_click(view, "read_card", %{"card" => "1"})
    assert :sys.get_state(view.pid).socket.assigns.zoom == nil

    # malformed values are ignored instead of crashing the LiveView
    for {event, key} <- [{"zoom_card", "card"}, {"read_card", "card"}, {"answer", "choice"}],
        value <- [1, nil, %{"x" => 1}, "-1", "abc"] do
      render_click(view, event, %{key => value})
    end

    assert Process.alive?(view.pid)
    assert :sys.get_state(view.pid).socket.assigns.zoom == nil
    assert has_element?(view, "#choice-0")

    # the hover texts work on thumbnails: nothing lies over the card
    refute has_element?(view, "#question-card-0 button.absolute")

    # a tap on the text box opens the texts in a readable panel
    view |> element("#question-card-0 .mq-card__texts") |> render_click()
    assert has_element?(view, "#card-text .mq-card-panel__body", "Select 1 monster")
    assert has_element?(view, "#card-text a[href='https://yugipedia.com']")
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

  describe "card links in the question text" do
    @text "Use [Monster Reborn] then [Plain Card] and [Unknown]"

    defp start_with_text(conn, text, card_ids) do
      format = format_fixture(%{"date" => "2020-01-01"})

      questions =
        for topic <- format.topics do
          {:ok, q} =
            Quiz.create_question(
              topic,
              %{"text" => text, "choices" => choices_params()},
              card_ids
            )

          q
        end

      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")
      view |> element("#question-0") |> render_click()
      {view, id, questions}
    end

    defp snapshot_question(view),
      do: MillenniumQuiz.Game.current_question(:sys.get_state(view.pid).socket.assigns.game)

    test "resolve against the snapshot in both views", %{conn: conn} do
      CardSourcesStub.stub!()
      {:ok, reborn} = Cards.import(83_764_719)
      {:ok, plain} = Cards.import(11_111_111)
      {view, _id, _qs} = start_with_text(conn, @text, [reborn.id, plain.id])

      assert [
               {:text, "Use "},
               {:card, "Monster Reborn", 0},
               {:text, " then "},
               {:card, "Plain Card", 1},
               {:text, " and [Unknown]"}
             ] =
               MillenniumQuizWeb.GameLive.question_segments(snapshot_question(view))

      assert has_element?(view, "#question-text", "Use Monster Reborn then Plain Card")
      assert has_element?(view, "#question-text", "and [Unknown]")
      assert has_element?(view, "#question-text [data-card-index=\"0\"]", "Monster Reborn")
      assert has_element?(view, "#question-text [data-card-index=\"1\"]", "Plain Card")
      refute has_element?(view, "#question-text [data-card-index=\"2\"]")

      view |> element("#choice-0") |> render_click()
      view |> element("#choice-0") |> render_click()
      assert has_element?(view, "#reveal #question-text", "and [Unknown]")
      assert has_element?(view, "#reveal #question-text [data-card-index=\"1\"]", "Plain Card")
    end

    test "links are buttons that open the enlarged card, while answering and on reveal",
         %{conn: conn} do
      CardSourcesStub.stub!()
      {:ok, reborn} = Cards.import(83_764_719)
      {:ok, plain} = Cards.import(11_111_111)
      {view, _id, _qs} = start_with_text(conn, @text, [reborn.id, plain.id])

      assert has_element?(
               view,
               "#question-link-0[type=button][phx-click=zoom_card][phx-value-card=\"0\"][aria-label=\"Show card: Monster Reborn\"]",
               "Monster Reborn"
             )

      assert has_element?(view, "#question-link-1[phx-value-card=\"1\"]", "Plain Card")
      refute has_element?(view, "#question-link-2")
      refute has_element?(view, "#question-text button", "Unknown")

      # one hidden, decorative popover per distinct linked card
      assert has_element?(view, "#question-link-popovers[aria-hidden=true]")
      assert has_element?(view, "#question-link-popover-0 .mq-card", "Monster Reborn")
      assert has_element?(view, "#question-link-popover-1 .mq-card")
      refute has_element?(view, "#question-link-popovers button")

      view |> element("#question-link-1") |> render_click()
      assert has_element?(view, "#card-zoom .mq-card--large", "Plain Card")
      assert :sys.get_state(view.pid).socket.assigns.zoom == {:card, 1}

      view |> element("#card-zoom") |> render_keydown(%{"key" => "Escape"})
      refute has_element?(view, "#card-zoom")

      view |> element("#choice-0") |> render_click()
      view |> element("#choice-0") |> render_click()
      view |> element("#reveal #question-link-0") |> render_click()
      assert has_element?(view, "#card-zoom .mq-card--large", "Monster Reborn")
      assert :sys.get_state(view.pid).socket.assigns.zoom == {:card, 0}
    end

    test "a repeated card links twice but has one popover", %{conn: conn} do
      CardSourcesStub.stub!()
      {:ok, reborn} = Cards.import(83_764_719)

      {view, _id, _qs} =
        start_with_text(conn, "[Monster Reborn] and [Monster Reborn]", [reborn.id])

      assert has_element?(view, "#question-link-0[phx-value-card=\"0\"]")
      assert has_element?(view, "#question-link-1[phx-value-card=\"0\"]")

      assert [_] =
               view
               |> render()
               |> LazyHTML.from_fragment()
               |> LazyHTML.query(".mq-linkpop")
               |> Enum.to_list()
    end

    test "plain texts render unchanged", %{conn: conn} do
      CardSourcesStub.stub!()
      {:ok, reborn} = Cards.import(83_764_719)
      {view, _id, _qs} = start_with_text(conn, "Who? [sic]", [reborn.id])

      assert [{:text, "Who? [sic]"}] =
               MillenniumQuizWeb.GameLive.question_segments(snapshot_question(view))

      assert has_element?(view, "#question-text", "Who? [sic]")
      refute has_element?(view, "#question-text [data-card-index]")
      refute has_element?(view, "#question-text button")
      refute has_element?(view, "#question-link-popovers")
    end

    test "a running game keeps its markup when the question changes", %{conn: conn} do
      CardSourcesStub.stub!()
      {:ok, reborn} = Cards.import(83_764_719)
      {:ok, plain} = Cards.import(11_111_111)
      {view, id, [q | _]} = start_with_text(conn, @text, [reborn.id, plain.id])

      {:ok, _} = Quiz.update_question(q, %{"text" => "Changed"}, [plain.id])
      {:ok, _} = Quiz.update_question(Quiz.get_question!(q.id), %{"text" => "Again"}, [])

      {:ok, view2, _html} = live(conn, ~p"/games/#{id}")
      assert has_element?(view2, "#question-text [data-card-index=\"0\"]", "Monster Reborn")
      assert has_element?(view2, "#question-text [data-card-index=\"1\"]", "Plain Card")
      assert has_element?(view2, "#question-text", "and [Unknown]")
      assert [_, _] = snapshot_question(view).cards
    end
  end

  describe "cycle_card" do
    defp zoom_of(view), do: :sys.get_state(view.pid).socket.assigns.zoom

    defp start_with_cards(conn, card_ids) do
      format = format_fixture(%{"date" => "2020-01-01"})

      for topic <- format.topics do
        {:ok, _} =
          Quiz.create_question(
            topic,
            %{"text" => "Who?", "choices" => choices_params()},
            card_ids
          )
      end

      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")
      view |> element("#question-0") |> render_click()
      view
    end

    test "steps through the cards of a question, wrapping around", %{conn: conn} do
      CardSourcesStub.stub!()
      {:ok, reborn} = Cards.import(83_764_719)
      {:ok, plain} = Cards.import(11_111_111)
      view = start_with_cards(conn, [reborn.id, plain.id])

      # nothing is open: nothing to cycle
      render_hook(view, "cycle_card", %{"dir" => "next"})
      assert zoom_of(view) == nil

      for kind <- [:card, :text] do
        event = if kind == :card, do: "zoom_card", else: "read_card"
        render_hook(view, event, %{"card" => "0"})

        render_hook(view, "cycle_card", %{"dir" => "next"})
        assert zoom_of(view) == {kind, 1}
        render_hook(view, "cycle_card", %{"dir" => "next"})
        assert zoom_of(view) == {kind, 0}
        render_hook(view, "cycle_card", %{"dir" => "prev"})
        assert zoom_of(view) == {kind, 1}
        render_hook(view, "cycle_card", %{"dir" => "prev"})
        assert zoom_of(view) == {kind, 0}

        # malformed values are ignored
        for params <- [%{}, %{"dir" => nil}, %{"dir" => 1}, %{"dir" => "up"}, %{"dir" => %{}}] do
          render_hook(view, "cycle_card", params)
        end

        assert zoom_of(view) == {kind, 0}
        render_hook(view, "close_card", %{})
      end

      assert zoom_of(view) == nil
    end

    test "does nothing for a question with a single card", %{conn: conn} do
      CardSourcesStub.stub!()
      {:ok, reborn} = Cards.import(83_764_719)
      view = start_with_cards(conn, [reborn.id])

      render_hook(view, "zoom_card", %{"card" => "0"})
      render_hook(view, "cycle_card", %{"dir" => "next"})
      assert zoom_of(view) == {:card, 0}
      render_hook(view, "cycle_card", %{"dir" => "prev"})
      assert zoom_of(view) == {:card, 0}
    end

    test "the rendered buttons step through the cards in both views", %{conn: conn} do
      CardSourcesStub.stub!()
      {:ok, reborn} = Cards.import(83_764_719)
      {:ok, plain} = Cards.import(11_111_111)
      view = start_with_cards(conn, [reborn.id, plain.id])

      view |> element("#zoom-card-0") |> render_click()
      assert has_element?(view, "#card-zoom-cycle", "1 / 2")

      view |> element("#card-zoom-next") |> render_click()
      assert zoom_of(view) == {:card, 1}
      assert has_element?(view, "#card-zoom-cycle", "2 / 2")
      assert has_element?(view, "#card-zoom-cycle .mq-cycle__dot[aria-current]:nth-child(2)")

      view |> element("#card-zoom-next") |> render_click()
      assert zoom_of(view) == {:card, 0}
      view |> element("#card-zoom-prev") |> render_click()
      assert zoom_of(view) == {:card, 1}

      render_hook(view, "read_card", %{"card" => "1"})
      assert has_element?(view, "#card-text-cycle", "2 / 2")
      view |> element("#card-text-prev") |> render_click()
      assert zoom_of(view) == {:text, 0}
      view |> element("#card-text-next") |> render_click()
      assert zoom_of(view) == {:text, 1}

      # back to the card returns to the shown one
      view |> element("#card-text-back") |> render_click()
      assert zoom_of(view) == {:card, 1}
    end

    test "a single card shows no controls", %{conn: conn} do
      CardSourcesStub.stub!()
      {:ok, reborn} = Cards.import(83_764_719)
      view = start_with_cards(conn, [reborn.id])

      view |> element("#zoom-card-0") |> render_click()
      assert has_element?(view, "#card-zoom")
      refute has_element?(view, ".mq-cycle")
      refute has_element?(view, "#card-zoom-next")

      render_hook(view, "read_card", %{"card" => "0"})
      assert has_element?(view, "#card-text")
      refute has_element?(view, ".mq-cycle")
    end
  end

  describe "turn lock" do
    setup do
      Application.put_env(:millennium_quiz, :turn_lock_ms, 60_000)
      on_exit(fn -> Application.put_env(:millennium_quiz, :turn_lock_ms, 0) end)
    end

    defp turn_key(view), do: :sys.get_state(view.pid).socket.assigns.turn_key

    defp unlock(view), do: send(view.pid, {:unlock_turn, turn_key(view)})

    defp answering_game(conn, format) do
      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"], mode: :free)
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")
      # mounting never locks
      view |> element("#question-0") |> render_click()
      {id, view}
    end

    test "answers are ignored right after a turn starts, then work", %{conn: conn, format: format} do
      {id, view} = answering_game(conn, format)

      assert has_element?(view, "#choice-0[disabled]")
      render_click(view, "answer", %{"choice" => "0"})
      assert {:ok, %{game: %{answered: 0}}} = Games.fetch_game(id)
      assert has_element?(view, "#answer-progress", "1/2")

      unlock(view)
      refute has_element?(view, "#choice-0[disabled]")
      view |> element("#choice-0") |> render_click()
      assert {:ok, %{game: %{answered: 1}}} = Games.fetch_game(id)
    end

    test "the next player's turn locks again", %{conn: conn, format: format} do
      {id, view} = answering_game(conn, format)
      unlock(view)
      view |> element("#choice-0") |> render_click()

      assert has_element?(view, "#answer-progress", "2/2")
      assert has_element?(view, "#choice-0[disabled]")
      render_click(view, "answer", %{"choice" => "1"})
      assert {:ok, %{game: %{answered: 1}}} = Games.fetch_game(id)
    end

    test "a stale unlock does not unlock a newer turn", %{conn: conn, format: format} do
      {_id, view} = answering_game(conn, format)
      stale = turn_key(view)
      unlock(view)
      view |> element("#choice-0") |> render_click()

      send(view.pid, {:unlock_turn, stale})
      assert has_element?(view, "#choice-0[disabled]")
    end

    test "the reveal and the board lock too", %{conn: conn, format: format} do
      {id, view} = answering_game(conn, format)
      unlock(view)
      view |> element("#choice-0") |> render_click()
      unlock(view)
      view |> element("#choice-1") |> render_click()

      assert has_element?(view, "#next-round[disabled]")
      render_click(view, "next_round", %{})
      assert {:ok, %{game: %{phase: :revealed}}} = Games.fetch_game(id)

      unlock(view)
      view |> element("#next-round") |> render_click()
      assert has_element?(view, "#question-1[disabled]")
      render_click(view, "choose", %{"question" => "1"})
      assert {:ok, %{game: %{phase: :choosing}}} = Games.fetch_game(id)
    end

    test "a game mounted mid-turn is usable at once", %{conn: conn, format: format} do
      {id, _view} = answering_game(conn, format)
      {:ok, other, _html} = live(build_conn(), ~p"/games/#{id}")

      refute has_element?(other, "#choice-0[disabled]")
      other |> element("#choice-0") |> render_click()
      assert {:ok, %{game: %{answered: 1}}} = Games.fetch_game(id)
    end

    test "pause, zoom and ending still work while locked", %{conn: conn, format: format} do
      {_id, view} = answering_game(conn, format)

      view |> element("#end-game") |> render_click()
      assert has_element?(view, "#end-game-modal")
      view |> element("#cancel-end") |> render_click()

      render_click(view, "zoom_card", %{"card" => "0"})
      view |> element("#pause-game") |> render_click()
      assert has_element?(view, "#paused")
      view |> element("#resume-game") |> render_click()
      assert has_element?(view, "#choice-0[disabled]")
    end
  end

  test "unknown games redirect home", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/games/#{Ecto.UUID.generate()}")
  end
end
