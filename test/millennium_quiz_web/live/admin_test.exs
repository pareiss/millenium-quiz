defmodule MillenniumQuizWeb.AdminTest do
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.AccountsFixtures
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.Quiz

  test "admin pages require login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/categories")
    assert redirected_to(get(conn, ~p"/admin/users")) == ~p"/admin/login"
  end

  describe "login" do
    test "with valid credentials", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/admin/login",
          user: %{username: user.username, password: valid_user_password()}
        )

      assert redirected_to(conn) == ~p"/admin/categories"
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

    test "creates a category with topics", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/categories/new")

      # "Add topic" dispatches a form change with topics_sort[]=new
      view
      |> form("#category-form")
      |> render_change(%{category: %{topics_sort: ["0", "1", "new"]}})

      assert has_element?(view, "input[name='category[topics][2][name]']")

      result =
        view
        |> form("#category-form",
          category: %{
            name: "Card Lore",
            topics: %{
              "0" => %{name: "Monsters"},
              "1" => %{name: "Spells"},
              "2" => %{name: "Traps"}
            }
          }
        )
        |> render_submit()

      assert {:error, {:live_redirect, %{to: "/admin/categories/" <> id}}} = result
      assert Enum.map(Quiz.get_category!(id).topics, & &1.name) == ["Monsters", "Spells", "Traps"]
    end

    test "creates a question with default points and reorders it", %{conn: conn} do
      category = category_fixture()
      topic = hd(category.topics)
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

      {:ok, show, _html} = live(conn, ~p"/admin/categories/#{category.id}")
      [_, second] = Quiz.get_category!(category.id).topics |> hd() |> Map.fetch!(:questions)
      assert second.text == "Which card draws 2?"

      show |> element("#move-up-#{second.id}") |> render_click()
      assert Quiz.get_question!(second.id).position == 0
      assert Quiz.get_question!(first.id).position == 1
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
