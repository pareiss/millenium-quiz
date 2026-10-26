defmodule MillenniumQuizWeb.SuggestLiveTest do
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{Quiz, Repo}
  alias MillenniumQuiz.Quiz.Submission

  setup do
    format = format_fixture()
    %{format: format, topic: hd(format.topics)}
  end

  defp fill(view, format, topic, extra \\ %{}) do
    view
    |> form("#suggest-form", %{
      "format_id" => format.id,
      "topic_id" => topic.id,
      "submission" =>
        Map.merge(
          %{
            "text" => "Which card is [Dark Hole]?",
            "choices" => %{
              "0" => %{"text" => "Right", "correct" => "true"},
              "1" => %{"text" => "Wrong"}
            }
          },
          extra
        )
    })
  end

  test "the home page links to it", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#suggest-link[href='/suggest']")
  end

  test "explains the [Card Name] markup", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/suggest")
    assert has_element?(view, "#card-markup-help", "square brackets")
    assert has_element?(view, "#card-markup-help", "Monster Reborn")
  end

  test "sends a suggestion and shows its private status page", %{conn: conn, format: f, topic: t} do
    {:ok, view, _} = live(conn, ~p"/suggest")

    # the topic list follows the format
    view |> element("#suggest-form") |> render_change(%{"format_id" => f.id})
    assert has_element?(view, "#suggest-topic option", t.name)

    assert {:error, {:live_redirect, _}} =
             fill(view, f, t, %{"submitter_name" => "Yugi"}) |> render_submit()

    [s] = Repo.all(Submission)
    assert s.status == "pending" and s.submitter_name == "Yugi" and s.topic_id == t.id

    {:ok, page, html} = live(conn, ~p"/suggest/#{s.token}")
    assert html =~ "Waiting for an admin"
    assert has_element?(page, "#suggestion-copy", "Which card is Dark Hole?")

    {:ok, page, _} = live(conn, ~p"/suggest/#{s.token}")
    Quiz.reject_submission(s)
    {:ok, _page, html} = live(conn, ~p"/suggest/#{s.token}")
    assert html =~ "was not added"
    assert has_element?(page, "#suggestion-status")
  end

  test "needs a topic and a valid question", %{conn: conn, format: f, topic: t} do
    {:ok, view, _} = live(conn, ~p"/suggest")
    html = view |> form("#suggest-form", %{"submission" => %{"text" => "x"}}) |> render_submit()
    assert html =~ "Choose a format and a topic first."

    view |> element("#suggest-form") |> render_change(%{"format_id" => f.id})
    html = fill(view, f, t, %{"text" => ""}) |> render_submit()
    assert html =~ "can&#39;t be blank"
    assert Repo.all(Submission) == []
  end

  test "a filled honeypot stores nothing but looks fine", %{conn: conn, format: f, topic: t} do
    {:ok, view, _} = live(conn, ~p"/suggest")
    view |> element("#suggest-form") |> render_change(%{"format_id" => f.id})

    render_submit(view, "submit", %{"website" => "http://spam", "submission" => %{}})
    assert_redirect(view, ~p"/suggest/thanks")
    assert Repo.all(Submission) == []
    assert t
  end

  test "an unknown link goes back to the form", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/suggest"}}} = live(conn, ~p"/suggest/unknown")
  end

  describe "rate limit" do
    setup do
      # the counters live in ETS and outlast a test
      :ets.delete_all_objects(MillenniumQuiz.RateLimit.Backend)

      Application.put_env(:millennium_quiz, MillenniumQuiz.RateLimit,
        enabled: true,
        limits: [submit_ip: {1, 60_000}]
      )

      on_exit(fn ->
        :ets.delete_all_objects(MillenniumQuiz.RateLimit.Backend)
        Application.put_env(:millennium_quiz, MillenniumQuiz.RateLimit, enabled: false)
      end)
    end

    test "a form with mistakes does not use up the limit", %{conn: conn, format: f, topic: t} do
      {:ok, view, _} = live(conn, ~p"/suggest")
      view |> element("#suggest-form") |> render_change(%{"format_id" => f.id})

      for _ <- 1..3 do
        html = fill(view, f, t, %{"text" => ""}) |> render_submit()
        assert html =~ "can&#39;t be blank"
        refute html =~ "sent a lot of suggestions"
      end

      assert {:error, {:live_redirect, _}} = fill(view, f, t) |> render_submit()
      assert length(Repo.all(Submission)) == 1
    end

    test "stops a client sending many", %{conn: conn, format: f, topic: t} do
      {:ok, view, _} = live(conn, ~p"/suggest")
      view |> element("#suggest-form") |> render_change(%{"format_id" => f.id})
      assert {:error, {:live_redirect, _}} = fill(view, f, t) |> render_submit()

      {:ok, view, _} = live(conn, ~p"/suggest")
      view |> element("#suggest-form") |> render_change(%{"format_id" => f.id})
      html = fill(view, f, t) |> render_submit()
      assert html =~ "sent a lot of suggestions"
      assert length(Repo.all(Submission)) == 1
    end
  end
end
