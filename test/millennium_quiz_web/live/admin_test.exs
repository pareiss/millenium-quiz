defmodule MillenniumQuizWeb.AdminTest do
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.AccountsFixtures
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{CardSourcesStub, Quiz}

  test "admin pages require login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/formats")
    assert redirected_to(get(conn, ~p"/admin/users")) == ~p"/admin/login"
  end

  describe "login" do
    test "with valid credentials", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/admin/login",
          user: %{username: user.username, password: valid_user_password()}
        )

      assert redirected_to(conn) == ~p"/admin/formats"
      assert get_session(conn, :user_token)
    end

    test "with invalid credentials", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/admin/login",
          user: %{username: user.username, password: "wrong password!"}
        )

      assert redirected_to(conn) == ~p"/admin/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid username or password"
    end

    test "logout", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> delete(~p"/admin/logout")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end
  end

  test "without a login the header has no admin menu", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#admin-menu")
    assert has_element?(view, "#site-header a[href='/admin/login']")
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "the header folds the admin links into a menu on phones", %{conn: conn} do
      format = format_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format}")

      assert has_element?(view, "#brand-link[aria-label='Millennium Quiz']")
      assert has_element?(view, "#logout-link")
      assert has_element?(view, "#admin-menu [aria-label='Admin menu']")
      assert has_element?(view, "#admin-menu a#menu-formats")
      assert has_element?(view, "#admin-menu a#menu-users")
      assert has_element?(view, "#admin-menu a#menu-logout[data-method=delete]")
    end

    test "creates a format with topics", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/formats/new")

      # "Add topic" dispatches a form change with topics_sort[]=new
      view
      |> form("#format-form")
      |> render_change(%{format: %{topics_sort: ["0", "1", "new"]}})

      assert has_element?(view, "input[name='format[topics][2][name]']")

      result =
        view
        |> form("#format-form",
          format: %{
            name: "Card Lore",
            date: "2005-04-01",
            topics: %{
              "0" => %{name: "Monsters"},
              "1" => %{name: "Spells"},
              "2" => %{name: "Traps"}
            }
          }
        )
        |> render_submit()

      assert {:error, {:live_redirect, %{to: "/admin/formats/" <> id}}} = result
      format = Quiz.get_format!(id)
      assert format.date == ~D[2005-04-01]
      assert Enum.map(format.topics, & &1.name) == ["Monsters", "Spells", "Traps"]
    end

    test "the question textarea carries the card link hook and its suggestion list",
         %{conn: conn} do
      topic = hd(format_fixture().topics)
      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")

      assert has_element?(
               view,
               "textarea#question_text[phx-hook='CardLinkInput'][data-suggestions='question-text-suggestions'][aria-autocomplete='list'][maxlength='1000']"
             )

      assert has_element?(
               view,
               "ul#question-text-suggestions[role='listbox'][phx-update='ignore'][hidden]"
             )
    end

    test "the answer fields have the card name autocomplete (bare names)", %{conn: conn} do
      topic = hd(format_fixture().topics)
      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")

      for i <- 0..3 do
        assert has_element?(
                 view,
                 "input#question_choices_#{i}_text[phx-hook='CardLinkInput'][data-mode='plain'][data-suggestions='choice-suggestions-#{i}'][maxlength='200']"
               )

        assert has_element?(
                 view,
                 "ul#choice-suggestions-#{i}[role='listbox'][phx-update='ignore'][hidden]"
               )
      end

      refute has_element?(view, "#question_text[data-mode]")
      assert has_element?(view, "#choice-hint", "{P1}")
      assert has_element?(view, "#choice-hint", "this question's cards")
      assert has_element?(view, "input#question_choices_0_text[aria-describedby=choice-hint]")
    end

    test "creates a question with default points and reorders it", %{conn: conn} do
      format = format_fixture()
      topic = hd(format.topics)
      first = question_fixture(topic)

      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")
      assert has_element?(view, "input[name='question[points]'][placeholder^='20']")

      view
      |> form("#question-form",
        question: %{
          text: "Which card draws 2?",
          choices: %{
            "0" => %{text: "Pot of Greed", correct: "true"},
            "1" => %{text: "Dark Hole", correct: "false"},
            "2" => %{text: "Raigeki", correct: "false"},
            "3" => %{text: "Mirror Force", correct: "false"}
          }
        }
      )
      |> render_submit()

      {:ok, show, _html} = live(conn, ~p"/admin/formats/#{format.id}")
      [_, second] = Quiz.get_format!(format.id).topics |> hd() |> Map.fetch!(:questions)
      assert second.text == "Which card draws 2?"

      show |> element("#move-up-#{second.id}") |> render_click()
      assert Quiz.get_question!(second.id).position == 0
      assert Quiz.get_question!(first.id).position == 1
    end

    test "attaches cards from the search, showing the text of the format's date",
         %{conn: conn} do
      CardSourcesStub.stub!()
      format = format_fixture(%{"date" => "2004-06-01"})
      topic = hd(format.topics)

      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)

      # Plain Card (2015) didn't exist yet in a 2004 format
      view |> form("#card-search", card_search: %{query: "card"}) |> render_change()
      refute has_element?(view, "#card-results")

      view |> form("#card-search", card_search: %{query: "reborn"}) |> render_change()
      assert has_element?(view, "#card-results", "Monster Reborn")

      # a failing search clears the old results instead of showing them under the error
      Req.Test.stub(MillenniumQuiz.Cards, &Plug.Conn.send_resp(&1, 500, "down"))
      view |> form("#card-search", card_search: %{query: "rebor"}) |> render_change()
      assert has_element?(view, "#card-search-error")
      refute has_element?(view, "#card-results")

      CardSourcesStub.stub!()
      view |> form("#card-search", card_search: %{query: "reborn"}) |> render_change()
      view |> element("#add-card-83764719") |> render_click()
      render_async(view)

      assert has_element?(view, "#selected-cards", "Monster Reborn")
      assert has_element?(view, "#selected-cards", "as printed in Starter Deck: Yugi Evolution")

      assert has_element?(
               view,
               "#selected-cards",
               "Select 1 monster from either you or your opponent"
             )

      view
      |> form("#question-form",
        question: %{
          text: "Can it revive a monster from your own Graveyard?",
          choices: %{
            "0" => %{text: "Yes", correct: "true"},
            "1" => %{text: "No", correct: "false"},
            "2" => %{text: "Only Spellcasters", correct: "false"},
            "3" => %{text: "Only with 1000 LP", correct: "false"}
          }
        }
      )
      |> render_submit()

      [question] = Quiz.get_format!(format.id).topics |> hd() |> Map.fetch!(:questions)
      question = Quiz.get_question!(question.id)
      assert [%{card: %{name: "Monster Reborn"}}] = question.question_cards

      # editing keeps the card, removing it detaches it
      {:ok, edit, _html} = live(conn, ~p"/admin/questions/#{question.id}/edit")
      [%{card: card}] = question.question_cards
      # a malformed id from the browser is ignored, not a crash
      render_hook(edit, "remove_card", %{"id" => "not-an-id"})
      assert has_element?(edit, "#selected-card-#{card.id}")
      edit |> element("#remove-card-#{card.id}") |> render_click()
      edit |> form("#question-form") |> render_submit()
      assert Quiz.get_question!(question.id).question_cards == []
    end

    test "suggests pool cards, falls back to the remote search and links cards",
         %{conn: conn} do
      CardSourcesStub.stub!()
      format = format_fixture(%{"date" => "2004-06-01"})
      topic = hd(format.topics)
      {:ok, reborn} = MillenniumQuiz.Cards.import(CardSourcesStub.reborn().password)

      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)

      # pool
      render_hook(view, "suggest_cards", %{"query" => "monster re"})
      assert_reply(view, %{suggestions: [%{id: id, name: "Monster Reborn", source: "pool"}]})
      assert id == reborn.id

      # too short, and malformed
      render_hook(view, "suggest_cards", %{"query" => "m"})
      assert_reply(view, %{suggestions: []})
      render_hook(view, "suggest_cards", %{"query" => 5})
      assert_reply(view, %{suggestions: []})

      # nothing in the pool: remote (Plain Card is from 2015 > 2004, so nothing for it)
      render_hook(view, "suggest_cards", %{"query" => "plain"})
      assert_reply(view, %{suggestions: []})

      # link a pool card, once
      render_hook(view, "link_card", %{"id" => to_string(reborn.id)})
      render_hook(view, "link_card", %{"id" => to_string(reborn.id)})
      assert has_element?(view, "#selected-card-#{reborn.id}")
      assert view |> render() |> String.split("id=\"selected-card-") |> length() == 2

      # bad params and unknown ids don't crash
      render_hook(view, "link_card", %{"id" => "x"})
      render_hook(view, "link_card", %{"id" => "999999999999999999999"})
      assert render_hook(view, "link_card", %{"id" => "424242"}) =~ "not in the card pool"
      render_hook(view, "link_card", %{"nothing" => 1})
      render_hook(view, "link_card", %{"password" => "abc"})
      assert has_element?(view, "#selected-cards")
    end

    test "remote fallback and linking a remote card imports it", %{conn: conn} do
      CardSourcesStub.stub!()
      format = format_fixture(%{"date" => "2004-06-01"})
      topic = hd(format.topics)

      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)

      render_hook(view, "suggest_cards", %{"query" => "reborn"})

      assert_reply(view, %{
        suggestions: [%{password: 83_764_719, name: "Monster Reborn", source: "remote"}]
      })

      render_hook(view, "link_card", %{"password" => "83764719"})
      render_async(view)
      assert has_element?(view, "#selected-cards", "Monster Reborn")

      # a failing remote search is an empty list, not a crash
      Req.Test.stub(MillenniumQuiz.Cards, &Plug.Conn.send_resp(&1, 500, "down"))
      render_hook(view, "suggest_cards", %{"query" => "dark"})
      assert_reply(view, %{suggestions: []})
    end

    test "an answer field suggests only the question's attached cards, without any request",
         %{conn: conn} do
      CardSourcesStub.stub!()
      {:ok, reborn} = MillenniumQuiz.Cards.import(CardSourcesStub.reborn().password)
      {:ok, _plain} = MillenniumQuiz.Cards.import(CardSourcesStub.plain().password)
      topic = hd(format_fixture(%{"date" => "2020-01-01"}).topics)

      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")
      # no Req.Test.allow: a request to a card source from the view would fail

      # nothing attached yet: both cards are in the pool, none is suggested
      render_hook(view, "suggest_cards", %{"query" => "monster", "scope" => "attached"})
      assert_reply(view, %{suggestions: []})

      render_hook(view, "link_card", %{"id" => to_string(reborn.id)})

      render_hook(view, "suggest_cards", %{"query" => "REBORN", "scope" => "attached"})
      assert_reply(view, %{suggestions: [%{id: id, name: "Monster Reborn", source: "pool"}]})
      assert id == reborn.id

      # too short; a pool card that is not attached; a name nobody has (no search)
      render_hook(view, "suggest_cards", %{"query" => "m", "scope" => "attached"})
      assert_reply(view, %{suggestions: []})
      render_hook(view, "suggest_cards", %{"query" => "plain", "scope" => "attached"})
      assert_reply(view, %{suggestions: []})
      render_hook(view, "suggest_cards", %{"query" => "zzzz", "scope" => "attached"})
      assert_reply(view, %{suggestions: []})
    end

    test "removing a card unlinks it in the current text; the text with links is saved",
         %{conn: conn} do
      CardSourcesStub.stub!()
      format = format_fixture(%{"date" => "2004-06-01"})
      topic = hd(format.topics)
      {:ok, reborn} = MillenniumQuiz.Cards.import(CardSourcesStub.reborn().password)

      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")
      render_hook(view, "link_card", %{"id" => to_string(reborn.id)})

      text = "Does [Monster Reborn] work [sic] on [monster reborn]?"

      form_params = %{
        text: text,
        points: "40",
        choices: %{
          "0" => %{text: "Yes", correct: "true"},
          "1" => %{text: "No", correct: "false"},
          "2" => %{text: "Maybe", correct: "false"},
          "3" => %{text: "Never", correct: "false"}
        }
      }

      view |> form("#question-form", question: form_params) |> render_change()
      view |> element("#remove-card-#{reborn.id}") |> render_click()

      assert_push_event(view, "card_links:set_text", %{
        text: "Does Monster Reborn work [sic] on monster reborn?"
      })

      html = view |> element("#question-form textarea") |> render()
      assert html =~ "Does Monster Reborn work [sic] on monster reborn?"
      assert has_element?(view, "#question-form input[name='question[points]'][value='40']")

      # saving keeps the markup as written and the cards from the list
      render_hook(view, "link_card", %{"id" => to_string(reborn.id)})

      view
      |> form("#question-form", question: %{form_params | text: "Does [Monster Reborn] work?"})
      |> render_submit()

      [question] = Quiz.get_format!(format.id).topics |> hd() |> Map.fetch!(:questions)
      question = Quiz.get_question!(question.id)
      assert question.text == "Does [Monster Reborn] work?"
      assert [%{card: %{name: "Monster Reborn"}}] = question.question_cards

      # the admin list shows it without brackets
      {:ok, _show, html} = live(conn, ~p"/admin/formats/#{format.id}")
      assert html =~ "Does Monster Reborn work?"
      refute html =~ "[Monster Reborn]"
    end

    test "the cards of a question can be moved up and down; the order is saved and loaded again",
         %{conn: conn} do
      CardSourcesStub.stub!()
      format = format_fixture(%{"date" => "2020-01-01"})
      topic = hd(format.topics)
      {:ok, reborn} = MillenniumQuiz.Cards.import(CardSourcesStub.reborn().password)
      {:ok, plain} = MillenniumQuiz.Cards.import(CardSourcesStub.plain().password)

      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")

      # one card has nothing to move past
      render_hook(view, "link_card", %{"id" => to_string(reborn.id)})
      refute has_element?(view, "#move-card-#{reborn.id}-up")

      render_hook(view, "link_card", %{"id" => to_string(plain.id)})
      order = fn v -> card_ids(render(v)) end

      assert order.(view) == [reborn.id, plain.id]

      # the ends cannot go further
      assert has_element?(view, "#move-card-#{reborn.id}-up[disabled]")
      assert has_element?(view, "#move-card-#{plain.id}-down[disabled]")
      refute has_element?(view, "#move-card-#{reborn.id}-down[disabled]")

      # an owner goes with its card
      view |> element("#owner-#{reborn.id}-1") |> render_click()
      view |> element("#move-card-#{reborn.id}-down") |> render_click()
      assert order.(view) == [plain.id, reborn.id]
      assert has_element?(view, "#owner-#{reborn.id}-1[aria-pressed=true]")

      # odd values change nothing
      render_hook(view, "move_card", %{"id" => to_string(plain.id), "dir" => "up"})
      render_hook(view, "move_card", %{"id" => "999999", "dir" => "up"})
      render_hook(view, "move_card", %{"id" => to_string(reborn.id), "dir" => "sideways"})
      render_hook(view, "move_card", %{})
      assert order.(view) == [plain.id, reborn.id]

      view
      |> form("#question-form",
        question: %{
          text: "Which is first?",
          points: "40",
          choices: %{
            "0" => %{text: "Yes", correct: "true"},
            "1" => %{text: "No", correct: "false"},
            "2" => %{text: "Maybe", correct: "false"},
            "3" => %{text: "Never", correct: "false"}
          }
        }
      )
      |> render_submit()

      [question] = Quiz.get_format!(format.id).topics |> hd() |> Map.fetch!(:questions)
      question = Quiz.get_question!(question.id)
      assert Enum.map(question.question_cards, & &1.card_id) == [plain.id, reborn.id]

      {:ok, edit, _html} = live(conn, ~p"/admin/questions/#{question.id}/edit")

      assert order.(edit) == [plain.id, reborn.id]

      # editing a saved question: move a card back, save, and the order and the owner are kept
      edit |> element("#move-card-#{plain.id}-down") |> render_click()
      assert order.(edit) == [reborn.id, plain.id]
      edit |> form("#question-form") |> render_submit()

      saved = Quiz.get_question!(question.id)

      assert Enum.map(saved.question_cards, &{&1.card_id, &1.owner}) == [
               {reborn.id, 1},
               {plain.id, nil}
             ]
    end

    test "a card gets an owner in the form; it is saved, loaded again and dropped with the card",
         %{conn: conn} do
      CardSourcesStub.stub!()
      format = format_fixture(%{"date" => "2020-01-01"})
      topic = hd(format.topics)
      {:ok, reborn} = MillenniumQuiz.Cards.import(CardSourcesStub.reborn().password)
      {:ok, plain} = MillenniumQuiz.Cards.import(CardSourcesStub.plain().password)

      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")
      render_hook(view, "link_card", %{"id" => to_string(reborn.id)})
      render_hook(view, "link_card", %{"id" => to_string(plain.id)})

      # nobody owns a card at first
      assert has_element?(view, "#owner-#{reborn.id}-none[aria-pressed=true]")
      assert has_element?(view, "#owner-#{reborn.id}-1[aria-pressed=false]")

      view |> element("#owner-#{reborn.id}-1") |> render_click()
      view |> element("#owner-#{plain.id}-2") |> render_click()
      assert has_element?(view, "#owner-#{reborn.id}-1[aria-pressed=true]")
      assert has_element?(view, "#owner-#{reborn.id}-none[aria-pressed=false]")
      assert has_element?(view, "#owner-#{plain.id}-2[aria-pressed=true]")

      # a card that is not attached, and odd values, change nothing
      render_hook(view, "set_owner", %{"id" => "999999", "owner" => "1"})
      render_hook(view, "set_owner", %{"id" => to_string(plain.id), "owner" => "3"})
      render_hook(view, "set_owner", %{"id" => "x", "owner" => "1"})
      assert has_element?(view, "#owner-#{plain.id}-2[aria-pressed=true]")

      params = %{
        text: "[Monster Reborn] against [Plain Card]",
        points: "10",
        choices: %{
          "0" => %{text: "Yes", correct: "true"},
          "1" => %{text: "No", correct: "false"},
          "2" => %{text: "Maybe", correct: "false"},
          "3" => %{text: "Never", correct: "false"}
        }
      }

      view |> form("#question-form", question: params) |> render_submit()
      [question] = Quiz.get_format!(format.id).topics |> hd() |> Map.fetch!(:questions)

      owners = fn q ->
        for qc <- Quiz.get_question!(q.id).question_cards, do: {qc.card.name, qc.owner}
      end

      assert owners.(question) == [{"Monster Reborn", 1}, {"Plain Card", 2}]

      # editing loads the owners; changing one and removing the other card
      {:ok, edit, _html} = live(conn, ~p"/admin/questions/#{question.id}/edit")
      assert has_element?(edit, "#owner-#{reborn.id}-1[aria-pressed=true]")
      assert has_element?(edit, "#owner-#{plain.id}-2[aria-pressed=true]")

      edit |> element("#owner-#{reborn.id}-none") |> render_click()
      edit |> element("#remove-card-#{plain.id}") |> render_click()
      edit |> form("#question-form", question: params) |> render_submit()
      assert owners.(question) == [{"Monster Reborn", nil}]

      # a card that comes back after being removed starts with nobody
      {:ok, edit, _html} = live(conn, ~p"/admin/questions/#{question.id}/edit")
      edit |> element("#owner-#{reborn.id}-2") |> render_click()
      edit |> element("#remove-card-#{reborn.id}") |> render_click()
      render_hook(edit, "link_card", %{"id" => to_string(reborn.id)})
      assert has_element?(edit, "#owner-#{reborn.id}-none[aria-pressed=true]")
    end

    test "link_card is idempotent for ids and passwords and doesn't re-import",
         %{conn: conn} do
      CardSourcesStub.stub!()
      format = format_fixture(%{"date" => "2004-06-01"})
      topic = hd(format.topics)
      {:ok, reborn} = MillenniumQuiz.Cards.import(CardSourcesStub.reborn().password)

      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)

      render_hook(view, "link_card", %{"id" => to_string(reborn.id)})
      render_hook(view, "link_card", %{"id" => to_string(reborn.id)})
      assert view |> render() |> String.split("id=\"selected-card-") |> length() == 2

      password = to_string(reborn.password)
      render_hook(view, "link_card", %{"password" => password})
      assert :sys.get_state(view.pid).socket.assigns.importing == nil
      refute render(view) =~ "already running"
      assert view |> render() |> String.split("id=\"selected-card-") |> length() == 2
    end

    test "a remote link during a running import shows a flash", %{conn: conn} do
      CardSourcesStub.stub!()
      format = format_fixture(%{"date" => "2004-06-01"})
      topic = hd(format.topics)

      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")

      test_pid = self()
      first = :atomics.new(1, [])

      Req.Test.stub(MillenniumQuiz.Cards, fn conn ->
        if :atomics.add_get(first, 1, 1) == 1 do
          send(test_pid, {:blocked, self()})

          receive do
            :go -> :ok
          after
            5_000 -> :ok
          end
        end

        CardSourcesStub.handle(conn)
      end)

      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)

      render_hook(view, "link_card", %{"password" => "83764719"})
      assert render_hook(view, "link_card", %{"password" => "11111111"}) =~ "already running"
      assert render_hook(view, "add_card", %{"password" => "11111111"}) =~ "already running"

      # a request from the import's own task is allowed through the view's allowance
      assert_receive {:blocked, blocked}, 2_000
      send(blocked, :go)
      render_async(view)
      assert has_element?(view, "#selected-cards", "Monster Reborn")
      refute has_element?(view, "#selected-cards", "Plain Card")
    end

    test "warns about bracketed names without an attached card, without blocking save",
         %{conn: conn} do
      CardSourcesStub.stub!()
      format = format_fixture(%{"date" => "2004-06-01"})
      topic = hd(format.topics)
      {:ok, reborn} = MillenniumQuiz.Cards.import(CardSourcesStub.reborn().password)

      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")
      refute has_element?(view, "#unlinked-names")

      params = fn text ->
        %{
          text: text,
          choices: %{
            "0" => %{text: "Yes", correct: "true"},
            "1" => %{text: "No", correct: "false"},
            "2" => %{text: "Maybe", correct: "false"},
            "3" => %{text: "Never", correct: "false"}
          }
        }
      end

      view
      |> form("#question-form",
        question: params.("Is [Monster Reborn] like [ Dark Hole ] and [sic]?")
      )
      |> render_change()

      assert has_element?(view, "#unlinked-names", "[Monster Reborn], [Dark Hole], [sic]")
      assert has_element?(view, "#unlinked-names[role='status']")

      render_hook(view, "link_card", %{"id" => to_string(reborn.id)})
      assert has_element?(view, "#unlinked-names", "[Dark Hole], [sic]")
      refute has_element?(view, "#unlinked-names", "Monster Reborn")

      view
      |> form("#question-form", question: params.("Is [monster reborn] fine?"))
      |> render_change()

      refute has_element?(view, "#unlinked-names")

      # removing the card brings the warning back as the brackets go away: none left
      view |> element("#remove-card-#{reborn.id}") |> render_click()
      refute has_element?(view, "#unlinked-names")

      # with brackets still in the text (typed after removal) saving isn't blocked
      view
      |> form("#question-form", question: params.("Is [Dark Hole] fine?"))
      |> render_submit()

      assert [%{text: "Is [Dark Hole] fine?"}] =
               Quiz.get_format!(format.id).topics |> hd() |> Map.fetch!(:questions)
    end

    test "the warning shows on mount of an edited question and after remove_card",
         %{conn: conn} do
      CardSourcesStub.stub!()
      format = format_fixture(%{"date" => "2004-06-01"})
      topic = hd(format.topics)
      {:ok, reborn} = MillenniumQuiz.Cards.import(CardSourcesStub.reborn().password)

      {:ok, question} =
        Quiz.create_question(
          topic,
          %{
            "text" => "Does [Monster Reborn] beat [Dark Hole]?",
            "choices" => %{
              "0" => %{"text" => "Yes", "correct" => "true"},
              "1" => %{"text" => "No", "correct" => "false"}
            }
          },
          [reborn.id]
        )

      {:ok, view, _html} = live(conn, ~p"/admin/questions/#{question.id}/edit")
      assert has_element?(view, "#unlinked-names", "[Dark Hole]")
      refute has_element?(view, "#unlinked-names", "Monster Reborn")

      # removing the card unlinks its name in the text, the other name stays
      view |> element("#remove-card-#{reborn.id}") |> render_click()
      assert has_element?(view, "#unlinked-names", "[Dark Hole]")
      refute has_element?(view, "#unlinked-names", "Reborn")

      # the card can be linked again by hand-edited text and a link event
      view
      |> form("#question-form", question: %{text: "Does [Monster Reborn] beat it?"})
      |> render_change()

      assert has_element?(view, "#unlinked-names", "[Monster Reborn]")
      render_hook(view, "link_card", %{"id" => to_string(reborn.id)})
      refute has_element?(view, "#unlinked-names")
    end

    test "the search box survives a text-started import, not a search-started one",
         %{conn: conn} do
      CardSourcesStub.stub!()
      format = format_fixture(%{"date" => "2004-06-01"})
      topic = hd(format.topics)

      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)

      view |> form("#card-search", card_search: %{query: "reborn"}) |> render_change()
      assert has_element?(view, "#card-results")

      render_hook(view, "link_card", %{"password" => "83764719"})
      render_async(view)
      assert has_element?(view, "#selected-cards", "Monster Reborn")
      assert has_element?(view, "#card-results")
      assert has_element?(view, "#card-search input[value='reborn']")

      view |> element("#add-card-83764719") |> render_click()
      render_async(view)
      refute has_element?(view, "#card-results")
      refute has_element?(view, "#card-search input[value='reborn']")
    end

    test "link_card by id rejects cards released after the format's date",
         %{conn: conn} do
      CardSourcesStub.stub!()
      format = format_fixture(%{"date" => "2004-06-01"})
      topic = hd(format.topics)
      {:ok, reborn} = MillenniumQuiz.Cards.import(CardSourcesStub.reborn().password)

      set_release = fn date ->
        reborn |> Ecto.Changeset.change(tcg_release_date: date) |> MillenniumQuiz.Repo.update!()
      end

      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")

      set_release.(~D[2015-01-01])

      assert render_hook(view, "link_card", %{"id" => to_string(reborn.id)}) =~
               "not in the card pool"

      refute has_element?(view, "#selected-card-#{reborn.id}")

      set_release.(~D[2004-06-01])
      render_hook(view, "link_card", %{"id" => to_string(reborn.id)})
      assert has_element?(view, "#selected-card-#{reborn.id}")
    end

    test "a format's date can't be changed after it was created", %{conn: conn} do
      format = format_fixture(%{"date" => "2004-06-01"})
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format.id}/edit")

      refute has_element?(view, "input[name='format[date]']")
      assert has_element?(view, "#format-date", "Jun 1, 2004")

      view
      |> form("#format-form", format: %{name: "Early 2004"})
      |> render_submit(%{format: %{date: "2020-01-01"}})

      assert %{name: "Early 2004", date: ~D[2004-06-01]} = Quiz.get_format!(format.id)
    end

    test "deleting a format asks in a dialog first", %{conn: conn} do
      format = format_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format.id}")

      view |> element("#delete-format") |> render_click()
      assert has_element?(view, "#delete-format-dialog", format.name)

      view |> element("#delete-format-dialog-cancel") |> render_click()
      refute has_element?(view, "#delete-format-dialog")

      # Esc and a click on the backdrop are wired to cancel
      view |> element("#delete-format") |> render_click()

      assert has_element?(
               view,
               "#delete-format-dialog[phx-window-keydown=cancel_confirm][phx-key=escape]"
             )

      assert has_element?(view, "#delete-format-dialog [phx-click=cancel_confirm]")
      view |> element("#delete-format-dialog-cancel") |> render_click()
      assert Quiz.get_format!(format.id)

      view |> element("#delete-format") |> render_click()

      assert {:error, {:live_redirect, %{to: "/admin/formats"}}} =
               view |> element("#delete-format-dialog-confirm") |> render_click()

      assert_raise Ecto.NoResultsError, fn -> Quiz.get_format!(format.id) end
    end

    test "deleting a question asks in a dialog first", %{conn: conn} do
      format = format_fixture()
      topic = hd(format.topics)
      keep = question_fixture(topic, %{"text" => "Which card draws 2?"})
      doomed = question_fixture(topic, %{"text" => "Which card destroys all monsters?"})
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format.id}")

      view |> element("#delete-question-#{doomed.id}") |> render_click()
      assert has_element?(view, "#delete-question-dialog", "Which card destroys all monsters?")

      view |> element("#delete-question-dialog-cancel") |> render_click()
      refute has_element?(view, "#delete-question-dialog")
      assert Quiz.get_question!(doomed.id)

      view |> element("#delete-question-#{doomed.id}") |> render_click()
      view |> element("#delete-question-dialog-confirm") |> render_click()

      refute has_element?(view, "#delete-question-dialog")
      refute has_element?(view, "#delete-question-#{doomed.id}")
      assert has_element?(view, "#delete-question-#{keep.id}")
      assert_raise Ecto.NoResultsError, fn -> Quiz.get_question!(doomed.id) end
    end

    test "a question deleted elsewhere is reported, not a crash", %{conn: conn} do
      format = format_fixture()
      question = question_fixture(hd(format.topics))
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format.id}")

      # another admin deletes it while this page is open
      {:ok, _} = Quiz.delete_question(question)
      view |> element("#delete-question-#{question.id}") |> render_click()
      assert render(view) =~ "That question doesn&#39;t exist anymore."
      refute has_element?(view, "#delete-question-dialog")

      # also when it disappears between opening the dialog and confirming
      other = question_fixture(hd(format.topics))
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format.id}")
      view |> element("#delete-question-#{other.id}") |> render_click()
      {:ok, _} = Quiz.delete_question(other)
      view |> element("#delete-question-dialog-confirm") |> render_click()
      assert render(view) =~ "That question doesn&#39;t exist anymore."
    end

    test "removing an admin asks in a dialog first", %{conn: conn, user: me} do
      other = user_fixture(%{username: "kaiba"})
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      refute has_element?(view, "#delete-user-#{me.id}")

      view |> element("#delete-user-#{other.id}") |> render_click()
      assert has_element?(view, "#delete-user-dialog", "Remove admin kaiba?")

      view |> element("#delete-user-dialog-cancel") |> render_click()
      refute has_element?(view, "#delete-user-dialog")
      assert has_element?(view, "#user-#{other.id}")

      view |> element("#delete-user-#{other.id}") |> render_click()
      view |> element("#delete-user-dialog-confirm") |> render_click()

      refute has_element?(view, "#user-#{other.id}")
      assert MillenniumQuiz.Repo.get(MillenniumQuiz.Accounts.User, other.id) == nil
    end

    test "admins can't remove themselves, and gone admins are reported", %{
      conn: conn,
      user: me
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # a forged event: there is no button for yourself
      render_click(view, "delete", %{"id" => to_string(me.id)})
      assert render(view) =~ "You can&#39;t remove yourself."
      refute render(view) =~ "removed."
      assert MillenniumQuiz.Repo.get(MillenniumQuiz.Accounts.User, me.id)

      other = user_fixture(%{username: "pegasus"})
      {:ok, view, _html} = live(conn, ~p"/admin/users")
      {:ok, _} = MillenniumQuiz.Accounts.delete_user(other)
      view |> element("#delete-user-#{other.id}") |> render_click()
      assert render(view) =~ "That admin doesn&#39;t exist anymore."
      refute has_element?(view, "#user-#{other.id}")
    end

    test "admins can add other admins", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> form("#new-user-form", user: %{username: "pegasus", password: valid_user_password()})
      |> render_submit()

      assert has_element?(view, "#users li", "pegasus")
    end

    test "changing the password logs in again", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/admin/password", %{
          "current_password" => valid_user_password(),
          "user" => %{
            "password" => "another password",
            "password_confirmation" => "another password"
          }
        })

      assert redirected_to(conn) == ~p"/admin/users"

      assert MillenniumQuiz.Accounts.get_user_by_username_and_password(
               user.username,
               "another password"
             )
    end
  end

  # the ids of the cards attached in the form, in the order shown
  defp card_ids(html) do
    ~r/id="selected-card-(\d+)"/
    |> Regex.scan(html)
    |> Enum.map(fn [_, id] -> String.to_integer(id) end)
  end
end
