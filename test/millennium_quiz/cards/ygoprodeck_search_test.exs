defmodule MillenniumQuiz.Cards.Sources.YGOPRODeckGateIntegrationTest do
  use ExUnit.Case, async: true

  alias MillenniumQuiz.CardSourcesStub
  alias MillenniumQuiz.Cards.Sources.YGOPRODeck
  alias MillenniumQuiz.Cards.Sources.YGOPRODeck.Gate

  setup do
    name = :"gate_#{System.unique_integer([:positive])}"

    start_supervised!(%{
      id: name,
      start:
        {Gate, :start_link,
         [[name: name, enabled: true, rate: 100, burst: 100, cache_ttl_ms: 60_000]]}
    })

    %{gate: name}
  end

  defp counting_stub(responder) do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(MillenniumQuiz.Cards, fn conn ->
      Agent.update(counter, &(&1 + 1))
      responder.(conn)
    end)

    fn -> Agent.get(counter, & &1) end
  end

  test "the same search is asked once, however it is typed", %{gate: gate} do
    requests = counting_stub(&CardSourcesStub.handle/1)

    assert {:ok, [%{name: "Monster Reborn"}]} = YGOPRODeck.search("monster re", gate: gate)
    assert {:ok, [%{name: "Monster Reborn"}]} = YGOPRODeck.search("  Monster RE ", gate: gate)
    assert requests.() == 1

    # another date is another question
    YGOPRODeck.search("monster re", gate: gate, before: ~D[2004-06-01])
    assert requests.() == 2
  end

  test "empty answers are cached too, errors are not", %{gate: gate} do
    requests = counting_stub(&CardSourcesStub.handle/1)
    assert {:ok, []} = YGOPRODeck.search("zzzzz", gate: gate)
    assert {:ok, []} = YGOPRODeck.search("zzzzz", gate: gate)
    assert requests.() == 1

    failing = counting_stub(&Plug.Conn.send_resp(&1, 500, "down"))
    assert {:error, {:http, 500}} = YGOPRODeck.search("kuriboh", gate: gate)
    assert {:error, {:http, 500}} = YGOPRODeck.search("kuriboh", gate: gate)
    # no retries behind the gate's back: one request per search
    assert failing.() == 2
  end

  test "a 429 opens the breaker: no more requests until it closes", %{gate: gate} do
    requests = counting_stub(&Plug.Conn.send_resp(&1, 429, "slow down"))

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, {:http, 429}} = YGOPRODeck.search("dark", gate: gate)
      end)

    assert log =~ "blocking us"
    assert {:error, :blocked} = YGOPRODeck.search("kuriboh", gate: gate)
    assert {:error, :blocked} = YGOPRODeck.search("kuriboh", gate: gate, priority: :player)
    assert requests.() == 1

    Gate.reset(gate)
    counting_stub(&CardSourcesStub.handle/1)
    assert {:ok, _} = YGOPRODeck.search("monster re", gate: gate)
  end

  test "a cached answer needs no permit, even while the breaker is open", %{gate: gate} do
    counting_stub(&CardSourcesStub.handle/1)
    assert {:ok, [_]} = YGOPRODeck.search("monster re", gate: gate)

    ExUnit.CaptureLog.capture_log(fn -> Gate.trip(nil, gate) end)
    assert {:ok, [_]} = YGOPRODeck.search("monster re", gate: gate, priority: :player)
  end
end
