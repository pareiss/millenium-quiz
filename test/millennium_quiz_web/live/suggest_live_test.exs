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

  test "says which cards are suggested once a format is chosen", %{conn: conn, format: f} do
    {:ok, view, _} = live(conn, ~p"/suggest")
    refute has_element?(view, "#card-date-note")

    view |> element("#suggest-form") |> render_change(%{"format_id" => f.id})
    assert has_element?(view, "#card-date-note", "released by")
    assert has_element?(view, "#card-date-note", "2005")

    view |> element("#suggest-form") |> render_change(%{"format_id" => ""})
    refute has_element?(view, "#card-date-note")
  end

  test "explains the [Card Name] markup", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/suggest")
    assert has_element?(view, "#card-markup-help", "square brackets")
    assert has_element?(view, "#card-markup-help", "Monster Reborn")
  end

  test "the answer fields have no card autocomplete (a suggestion has no cards)", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/suggest")

    for i <- 0..3 do
      assert has_element?(
               view,
               "input#submission_choices_#{i}_text[aria-describedby=choice-hint]:not([phx-hook])"
             )

      refute has_element?(view, "#choice-suggestions-#{i}")
    end

    assert has_element?(view, "#choice-hint", "{P1}")
    refute has_element?(view, "#choice-hint", "[")
    assert has_element?(view, "#card-markup-help", "{P2}")
    refute has_element?(view, "#card-markup-help", "suggestion list only inserts")
    # the question text keeps its list
    assert has_element?(view, "#submission_text[phx-hook=CardLinkInput]")
  end

  test "{P1} and {P2} show as badges on the status page", %{conn: conn, format: f, topic: t} do
    {:ok, view, _} = live(conn, ~p"/suggest")
    view |> element("#suggest-form") |> render_change(%{"format_id" => f.id})

    fill(view, f, t, %{
      "text" => "{P1} attacks [Dark Hole] of {P2}",
      "choices" => %{
        "0" => %{"text" => "{P1} wins", "correct" => "true"},
        "1" => %{"text" => "{P2} wins"}
      }
    })
    |> render_submit()

    [s] = Repo.all(Submission)
    {:ok, page, _} = live(conn, ~p"/suggest/#{s.token}")
    assert has_element?(page, "#suggestion-copy p .mq-player-badge", "P1")
    assert has_element?(page, "#suggestion-copy p .mq-player-badge", "P2")
    assert has_element?(page, "#suggestion-copy p", "attacks Dark Hole of")
    assert has_element?(page, "#suggestion-copy li .mq-player-badge", "P2")
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

    # the remote part answers `pending` and the names follow as an event
    defp remote(view, query) do
      render_hook(view, "suggest_cards", %{"query" => query})
      assert_reply(view, %{suggestions: [], pending: true})
      render_async(view)
    end

    defp choose_format(view, format),
      do: view |> element("#suggest-form") |> render_change(%{"format_id" => format.id})

    test "asks YGOPRODeck for a name the pool does not have, as a player, and lists names only",
         %{conn: conn} do
      late = format_fixture(%{"date" => "2020-06-01"})
      {:ok, view, _} = live(conn, ~p"/suggest")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)
      choose_format(view, late)

      # not in the pool (the stub's Plain Card), but known to YGOPRODeck
      remote(view, "plain")

      assert_push_event(view, "card_links:suggestions", %{
        query: "plain",
        suggestions: [%{name: "Plain Card", source: "name"}]
      })

      # too short for the remote search: answered at once, nothing is asked
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
      choose_format(view, late)

      render_hook(view, "suggest_cards", %{"query" => "monster re"})
      assert_reply(view, %{suggestions: [%{name: "Monster Reborn", source: "pool"}]})
    end

    test "a failing source is just no suggestion", %{conn: conn} do
      late = format_fixture(%{"date" => "2020-06-01"})
      {:ok, view, _} = live(conn, ~p"/suggest")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)
      choose_format(view, late)

      Req.Test.stub(MillenniumQuiz.Cards, &Plug.Conn.send_resp(&1, 500, "down"))
      remote(view, "plain")
      assert_push_event(view, "card_links:suggestions", %{query: "plain", suggestions: []})
    end

    test "the form is not held up while a lookup is waiting", %{conn: conn, topic: topic} do
      late = format_fixture(%{"date" => "2020-06-01"})
      {:ok, view, _} = live(conn, ~p"/suggest")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)
      choose_format(view, late)

      test_pid = self()

      Req.Test.stub(MillenniumQuiz.Cards, fn conn ->
        send(test_pid, {:asked, self()})
        receive do: (:go -> CardSourcesStub.handle(conn))
      end)

      render_hook(view, "suggest_cards", %{"query" => "plain"})
      assert_reply(view, %{suggestions: [], pending: true})
      assert_receive {:asked, task}

      # the lookup is stuck, the form still answers
      html =
        view
        |> form("#suggest-form", %{"submission" => %{"text" => "typing on"}})
        |> render_change()

      assert html =~ "typing on"
      assert topic

      send(task, :go)
      render_async(view)
      assert_push_event(view, "card_links:suggestions", %{query: "plain"})
    end

    test "one lookup at a time: of the queries typed meanwhile only the latest is asked",
         %{conn: conn} do
      late = format_fixture(%{"date" => "2020-06-01"})
      {:ok, view, _} = live(conn, ~p"/suggest")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)
      choose_format(view, late)

      test_pid = self()

      Req.Test.stub(MillenniumQuiz.Cards, fn conn ->
        send(test_pid, {:asked, self(), Plug.Conn.fetch_query_params(conn).query_params["fname"]})
        receive do: (:go -> CardSourcesStub.handle(conn))
      end)

      for query <- ["plain", "plain c", "plain ca", "plain car"] do
        render_hook(view, "suggest_cards", %{"query" => query})
        assert_reply(view, %{pending: true})
      end

      assert_receive {:asked, first, "plain"}
      send(first, :go)
      assert_receive {:asked, second, "plain car"}
      send(second, :go)
      render_async(view)
      refute_receive {:asked, _, _}, 50

      assert_push_event(view, "card_links:suggestions", %{query: "plain"})
      assert_push_event(view, "card_links:suggestions", %{query: "plain car"})
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

    defp lookup(view, query) do
      render_hook(view, "suggest_cards", %{"query" => query})
      assert_reply(view, %{pending: true})
      render_async(view)
    end

    defp open_form(conn) do
      late = format_fixture(%{"date" => "2020-06-01"})
      {:ok, view, _} = live(conn, ~p"/suggest")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)
      view |> element("#suggest-form") |> render_change(%{"format_id" => late.id})
      view
    end

    defp use_gate(opts) do
      alias MillenniumQuiz.Cards.Sources.YGOPRODeck.Gate
      name = :player_gate

      start_supervised!(%{
        id: name,
        start:
          {Gate, :start_link,
           [
             Keyword.merge(
               [
                 name: name,
                 enabled: true,
                 clock: &System.monotonic_time/1,
                 cache_ttl_ms: 0
               ],
               opts
             )
           ]}
      })

      Application.put_env(:millennium_quiz, :ygoprodeck_gate, name)
      name
    end

    test "players get the lowest priority at the gate", %{conn: conn} do
      alias MillenniumQuiz.Cards.Sources.YGOPRODeck.Gate
      # 4 permits, a player needs the bucket over half full; two admins take it down to 2
      gate = use_gate(burst: 4, rate: 1, player_wait_ms: 50)
      view = open_form(conn)

      assert Gate.acquire(:admin, gate) == :ok
      assert Gate.acquire(:admin, gate) == :ok

      lookup(view, "plain")
      assert_push_event(view, "card_links:suggestions", %{query: "plain", suggestions: []})

      # an admin could still search at that moment
      assert Gate.acquire(:admin, gate) == :ok
    end

    test "an open breaker is just no suggestion", %{conn: conn} do
      alias MillenniumQuiz.Cards.Sources.YGOPRODeck.Gate
      gate = use_gate(burst: 4)
      ExUnit.CaptureLog.capture_log(fn -> Gate.trip(nil, gate) end)
      view = open_form(conn)

      lookup(view, "plain")
      assert_push_event(view, "card_links:suggestions", %{query: "plain", suggestions: []})
    end

    test "a client is limited in lookups per minute", %{conn: conn} do
      Application.put_env(:millennium_quiz, MillenniumQuiz.RateLimit,
        enabled: true,
        limits: [suggest_remote_ip: {2, 60_000}]
      )

      view = open_form(conn)

      for query <- ["plain", "plain c"] do
        lookup(view, query)
        assert_push_event(view, "card_links:suggestions", %{query: ^query, suggestions: [_]})
      end

      lookup(view, "plain ca")
      assert_push_event(view, "card_links:suggestions", %{query: "plain ca", suggestions: []})
    end

    test "an answer from the cache does not count against the limit", %{conn: conn} do
      # a cache of the gate's own, so the repeated name is answered without a request
      use_gate(burst: 8, cache_ttl_ms: 60_000)

      Application.put_env(:millennium_quiz, MillenniumQuiz.RateLimit,
        enabled: true,
        limits: [suggest_remote_ip: {2, 60_000}]
      )

      view = open_form(conn)

      for _ <- 1..5 do
        lookup(view, "plain")
        assert_push_event(view, "card_links:suggestions", %{query: "plain", suggestions: [_]})
      end

      # only one real request was counted, so a second name is still allowed
      lookup(view, "plain c")
      assert_push_event(view, "card_links:suggestions", %{query: "plain c", suggestions: [_]})
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
