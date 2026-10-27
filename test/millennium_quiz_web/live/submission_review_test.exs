defmodule MillenniumQuizWeb.SubmissionReviewTest do
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ecto.Query
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{Quiz, Repo}

  setup do
    format = format_fixture()
    topic = hd(format.topics)

    {:ok, s} =
      Quiz.create_submission(topic, %{
        "text" => "What does [Monster Reborn] do?",
        "submitter_name" => "Yugi",
        "choices" => choices_params()
      })

    %{topic: topic, submission: s}
  end

  test "requires a login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/submissions")
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "lists pending suggestions and links the page", %{conn: conn, submission: s} do
      {:ok, view, _} = live(conn, ~p"/admin/submissions")
      assert has_element?(view, "#submission-#{s.id}", "Monster Reborn")
      assert has_element?(view, "#submission-#{s.id}", "by Yugi")
      assert has_element?(view, "#pending-count", "1")
      assert has_element?(view, "#menu-submissions")
    end

    test "the list draws {P1} and {P2} as badges", %{conn: conn, topic: topic} do
      {:ok, s} =
        Quiz.create_submission(topic, %{
          "text" => "{P1} attacks {P2}",
          "choices" => %{
            "0" => %{"text" => "{P2} loses", "correct" => "true"},
            "1" => %{"text" => "Nothing"}
          }
        })

      {:ok, view, _} = live(conn, ~p"/admin/submissions")
      assert has_element?(view, "#submission-#{s.id} p .mq-player-badge", "P1")
      assert has_element?(view, "#submission-#{s.id} li .mq-player-badge", "P2")
    end

    test "every filter opens, including the ones for reviewed suggestions", %{
      conn: conn,
      submission: s
    } do
      for status <- ~w(pending approved rejected all bogus) do
        {:ok, view, _} = live(conn, ~p"/admin/submissions?status=#{status}")
        assert has_element?(view, "#submission-filters")
      end

      {:ok, view, _} = live(conn, ~p"/admin/submissions?status=all")
      assert has_element?(view, "#submission-#{s.id}")
      {:ok, view, _} = live(conn, ~p"/admin/submissions?status=approved")
      refute has_element?(view, "#submission-#{s.id}")
    end

    test "the admin navigation shows how many are pending", %{conn: conn, submission: s} do
      {:ok, view, _} = live(conn, ~p"/admin/backup")
      assert has_element?(view, "#nav-pending", "1")

      Quiz.reject_submission(s)
      {:ok, view, _} = live(conn, ~p"/admin/backup")
      refute has_element?(view, "#nav-pending")
    end

    test "review opens a prefilled form and approving adds the question",
         %{conn: conn, topic: topic, submission: s} do
      {:ok, view, _} = live(conn, ~p"/admin/submissions")

      assert {:error, {:live_redirect, %{to: path}}} =
               view |> element("#review-#{s.id}") |> render_click()

      {:ok, form, html} = live(conn, path)
      assert has_element?(form, "#submission-original", "Yugi")
      assert has_element?(form, "#card-markup-help", "attach")
      assert html =~ "Monster Reborn"
      assert has_element?(form, "#unlinked-names", "Monster Reborn")
      assert has_element?(form, "input[name='question[submitted_by]'][value='Yugi']")

      assert {:error, {:live_redirect, %{to: "/admin/submissions"}}} =
               form
               |> form("#question-form", %{"question" => %{"text" => "Edited [Monster Reborn]?"}})
               |> render_submit()

      assert [q] = Quiz.get_topic!(topic.id) |> Repo.preload(:questions) |> Map.fetch!(:questions)
      assert q.text == "Edited [Monster Reborn]?"
      assert q.submitted_by == "Yugi"
      assert Quiz.get_submission(s.id).status == "approved"
      assert Quiz.get_submission(s.id).text == "What does [Monster Reborn] do?"
    end

    test "the admin can blank the name", %{conn: conn, topic: topic, submission: s} do
      {:ok, form, _} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new?submission=#{s.id}")
      form |> form("#question-form", %{"question" => %{"submitted_by" => ""}}) |> render_submit()
      [q] = Repo.all(from q in Quiz.Question, where: q.topic_id == ^topic.id)
      assert q.submitted_by == nil
    end

    test "a submission of another topic or an unknown one is not prefilled",
         %{conn: conn, topic: topic, submission: s} do
      other = Enum.find(Quiz.get_format!(topic.format_id).topics, &(&1.id != topic.id))
      {:ok, form, _} = live(conn, ~p"/admin/topics/#{other.id}/questions/new?submission=#{s.id}")
      refute has_element?(form, "#submission-original")
      {:ok, form, _} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new?submission=zzz")
      refute has_element?(form, "#submission-original")
    end

    test "the plain form also explains the markup", %{conn: conn, topic: topic} do
      {:ok, form, _} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")
      assert has_element?(form, "#card-markup-help", "square brackets")
      refute has_element?(form, "#submission-original")
      refute has_element?(form, "input[name='question[submitted_by]']")
    end

    test "rejecting keeps it under Rejected", %{conn: conn, submission: s} do
      {:ok, view, _} = live(conn, ~p"/admin/submissions")
      view |> element("#reject-#{s.id}") |> render_click()
      view |> element("#submission-dialog-confirm") |> render_click()
      refute has_element?(view, "#submission-#{s.id}")

      {:ok, view, _} = live(conn, ~p"/admin/submissions?status=rejected")
      assert has_element?(view, "#submission-#{s.id}")
      view |> element("#delete-#{s.id}") |> render_click()
      view |> element("#submission-dialog-confirm") |> render_click()
      assert Quiz.get_submission(s.id) == nil
    end
  end
end
