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

  describe "logged in" do
    setup :register_and_log_in_user

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
end
