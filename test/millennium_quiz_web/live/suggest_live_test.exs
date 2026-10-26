defmodule MillenniumQuizWeb.SuggestLiveTest do
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{CardSourcesStub, Quiz, Repo}
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

  describe "card name suggestions after a [" do
    setup do
      CardSourcesStub.stub!()
      {:ok, reborn} = MillenniumQuiz.Cards.import(CardSourcesStub.reborn().password)
      %{reborn: reborn}
    end

    test "the textarea has the autocomplete hook and its list", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/suggest")
      assert has_element?(view, "textarea[phx-hook=CardLinkInput][data-suggestions]")
      assert has_element?(view, "#question-text-suggestions[role=listbox]")
    end

    test "suggests pool cards released by the chosen format's date",
         %{conn: conn, reborn: reborn} do
      early = format_fixture(%{"date" => "2004-06-01"})
      late = format_fixture(%{"date" => "2020-06-01"})
      {:ok, view, _} = live(conn, ~p"/suggest")

      # no format yet: nothing
      render_hook(view, "suggest_cards", %{"query" => "monster re"})
      assert_reply(view, %{suggestions: []})

      view |> element("#suggest-form") |> render_change(%{"format_id" => late.id})
      render_hook(view, "suggest_cards", %{"query" => "monster re"})
      assert_reply(view, %{suggestions: [%{id: id, name: "Monster Reborn", source: "pool"}]})
      assert id == reborn.id

      # released after the format's date, too short, malformed
      view |> element("#suggest-form") |> render_change(%{"format_id" => early.id})
      render_hook(view, "suggest_cards", %{"query" => "plain"})
      assert_reply(view, %{suggestions: []})
      render_hook(view, "suggest_cards", %{"query" => "m"})
      assert_reply(view, %{suggestions: []})
      render_hook(view, "suggest_cards", %{"query" => 5})
      assert_reply(view, %{suggestions: []})
    end

    test "asks YGOPRODeck for a name the pool does not have, as a player, and lists names only",
         %{conn: conn} do
      late = format_fixture(%{"date" => "2020-06-01"})
      {:ok, view, _} = live(conn, ~p"/suggest")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)
      view |> element("#suggest-form") |> render_change(%{"format_id" => late.id})

      # not in the pool (the stub's Plain Card), but known to YGOPRODeck
      render_hook(view, "suggest_cards", %{"query" => "plain"})
      assert_reply(view, %{suggestions: [%{name: "Plain Card", source: "name"}]})

      # too short for the remote search
      render_hook(view, "suggest_cards", %{"query" => "pl"})
      assert_reply(view, %{suggestions: []})

      # choosing a card changes nothing on the server
      render_hook(view, "link_card", %{"id" => "1"})
      render_hook(view, "link_card", %{"password" => "83764719"})
      assert has_element?(view, "#suggest-form")
    end

    test "pool matches win: no request is made for them", %{conn: conn} do
      late = format_fixture(%{"date" => "2020-06-01"})
      Req.Test.stub(MillenniumQuiz.Cards, fn _ -> flunk("the card sources were asked") end)
      {:ok, view, _} = live(conn, ~p"/suggest")
      view |> element("#suggest-form") |> render_change(%{"format_id" => late.id})

      render_hook(view, "suggest_cards", %{"query" => "monster re"})
      assert_reply(view, %{suggestions: [%{name: "Monster Reborn", source: "pool"}]})
    end

    test "a busy gate or a failing source is just no suggestion", %{conn: conn} do
      late = format_fixture(%{"date" => "2020-06-01"})
      {:ok, view, _} = live(conn, ~p"/suggest")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)
      view |> element("#suggest-form") |> render_change(%{"format_id" => late.id})

      Req.Test.stub(MillenniumQuiz.Cards, &Plug.Conn.send_resp(&1, 500, "down"))
      render_hook(view, "suggest_cards", %{"query" => "plain"})
      assert_reply(view, %{suggestions: []})
    end
  end

  describe "card name lookups at YGOPRODeck: limits" do
    # not async-safe: the node's gate and the rate limits are swapped
    setup do
      CardSourcesStub.stub!()
      :ets.delete_all_objects(MillenniumQuiz.RateLimit.Backend)

      on_exit(fn ->
        :ets.delete_all_objects(MillenniumQuiz.RateLimit.Backend)
        Application.delete_env(:millennium_quiz, :ygoprodeck_gate)
        Application.put_env(:millennium_quiz, MillenniumQuiz.RateLimit, enabled: false)
      end)
    end

    test "players get the lowest priority at the gate", %{conn: conn} do
      alias MillenniumQuiz.Cards.Sources.YGOPRODeck.Gate
      name = :player_gate
      # 4 permits, a player needs the bucket over half full; two admins take it down to 2
      start_supervised!(%{
        id: name,
        start:
          {Gate, :start_link,
           [
             [
               name: name,
               enabled: true,
               burst: 4,
               rate: 1,
               player_wait_ms: 50,
               clock: &System.monotonic_time/1,
               cache_ttl_ms: 0
             ]
           ]}
      })

      Application.put_env(:millennium_quiz, :ygoprodeck_gate, name)
      late = format_fixture(%{"date" => "2020-06-01"})
      {:ok, view, _} = live(conn, ~p"/suggest")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)
      view |> element("#suggest-form") |> render_change(%{"format_id" => late.id})

      assert Gate.acquire(:admin, name) == :ok
      assert Gate.acquire(:admin, name) == :ok

      render_hook(view, "suggest_cards", %{"query" => "plain"})
      assert_reply(view, %{suggestions: []})

      # an admin could still search at that moment
      assert Gate.acquire(:admin, name) == :ok
    end

    test "a client is limited in lookups per minute", %{conn: conn} do
      Application.put_env(:millennium_quiz, MillenniumQuiz.RateLimit,
        enabled: true,
        limits: [suggest_remote_ip: {2, 60_000}]
      )

      late = format_fixture(%{"date" => "2020-06-01"})
      {:ok, view, _} = live(conn, ~p"/suggest")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)
      view |> element("#suggest-form") |> render_change(%{"format_id" => late.id})

      for query <- ["plain", "plain c"] do
        render_hook(view, "suggest_cards", %{"query" => query})
        assert_reply(view, %{suggestions: [%{name: "Plain Card"}]})
      end

      render_hook(view, "suggest_cards", %{"query" => "plain ca"})
      assert_reply(view, %{suggestions: []})
    end
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
