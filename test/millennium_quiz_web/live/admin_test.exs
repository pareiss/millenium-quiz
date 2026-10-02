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
      edit |> element("#remove-card-#{card.id}") |> render_click()
      edit |> form("#question-form") |> render_submit()
      assert Quiz.get_question!(question.id).question_cards == []
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
