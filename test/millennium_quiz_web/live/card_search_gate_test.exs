defmodule MillenniumQuizWeb.CardSearchGateTest do
  # not async: the gate is swapped through the application environment
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.Cards.Sources.YGOPRODeck.Gate

  setup :register_and_log_in_user

  # A gate of its own, as the node's gate for the test.
  defp use_gate(opts) do
    name = :"search_gate_#{System.unique_integer([:positive])}"

    start_supervised!(%{
      id: name,
      start: {Gate, :start_link, [Keyword.merge([name: name, enabled: true], opts)]}
    })

    Application.put_env(:millennium_quiz, :ygoprodeck_gate, name)
    on_exit(fn -> Application.delete_env(:millennium_quiz, :ygoprodeck_gate) end)
    name
  end

  defp search(conn) do
    topic = hd(format_fixture().topics)
    {:ok, view, _} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")

    view |> form("#card-search", %{"card_search" => %{"query" => "monster"}}) |> render_change()
    view
  end

  test "a busy gate says so and shows no results", %{conn: conn} do
    # one permit that is used up, and no time to wait for the next one
    gate = use_gate(burst: 1, rate: 1, admin_wait_ms: 50, clock: &System.monotonic_time/1)
    assert Gate.acquire(:admin, gate) == :ok

    view = search(conn)
    assert has_element?(view, "#card-search-error", "busy")
    refute has_element?(view, "#card-results")
  end

  test "a blocked gate says the search is not available", %{conn: conn} do
    gate = use_gate([])
    ExUnit.CaptureLog.capture_log(fn -> Gate.trip(nil, gate) end)

    view = search(conn)
    assert has_element?(view, "#card-search-error", "not available right now")
  end
end
