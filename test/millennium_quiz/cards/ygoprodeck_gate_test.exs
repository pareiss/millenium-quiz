defmodule MillenniumQuiz.Cards.Sources.YGOPRODeck.GateTest do
  use ExUnit.Case, async: true

  alias MillenniumQuiz.Cards.Sources.YGOPRODeck.Gate

  # A gate of its own per test, with a clock the test moves by hand (tests of
  # waiting out a deadline pass the real clock instead).
  defp start_gate(opts) do
    name = :"gate_#{System.unique_integer([:positive])}"
    {:ok, clock} = Agent.start_link(fn -> 0 end)
    clock_fn = fn _unit -> Agent.get(clock, & &1) end

    opts =
      Keyword.merge(
        [name: name, enabled: true, rate: 10, burst: 4, clock: clock_fn, cache_ttl_ms: 1_000],
        opts
      )

    start_supervised!(%{id: name, start: {Gate, :start_link, [opts]}})
    %{gate: name, advance: fn ms -> Agent.update(clock, &(&1 + ms)) end}
  end

  test "admins can use the whole bucket, then wait for new permits" do
    %{gate: g, advance: advance} = start_gate(admin_wait_ms: 200)

    assert for(_ <- 1..4, do: Gate.acquire(:admin, g)) == [:ok, :ok, :ok, :ok]

    task = Task.async(fn -> Gate.acquire(:admin, g) end)
    Process.sleep(60)
    advance.(100)
    assert Task.await(task) == :ok
  end

  test "a waiting request that gets nothing in time is told it is busy" do
    %{gate: g} =
      start_gate(burst: 1, rate: 1, admin_wait_ms: 100, clock: &System.monotonic_time/1)

    assert Gate.acquire(:admin, g) == :ok
    # about a tenth of a permit has come back by then
    assert Gate.acquire(:admin, g) == {:error, :busy}
  end

  test "players only get permits while the bucket is more than half full" do
    %{gate: g} =
      start_gate(
        burst: 4,
        rate: 1,
        player_floor: 0.5,
        player_wait_ms: 80,
        clock: &System.monotonic_time/1
      )

    # 4 tokens: a player may take 2 (down to the floor of 2), then must wait
    assert Gate.acquire(:player, g) == :ok
    assert Gate.acquire(:player, g) == :ok
    assert Gate.acquire(:player, g) == {:error, :busy}

    # the admins still have what is left
    assert Gate.acquire(:admin, g) == :ok
    assert Gate.acquire(:admin, g) == :ok
  end

  test "the player queue is bounded" do
    %{gate: g} =
      start_gate(
        burst: 1,
        rate: 1,
        player_queue: 2,
        player_wait_ms: 300,
        clock: &System.monotonic_time/1
      )

    tasks = for _ <- 1..2, do: Task.async(fn -> Gate.acquire(:player, g) end)
    Process.sleep(50)
    # two are waiting: the third is refused at once
    assert Gate.acquire(:player, g) == {:error, :busy}
    assert Enum.map(tasks, &Task.await/1) == [{:error, :busy}, {:error, :busy}]
  end

  test "admins waiting go before players" do
    %{gate: g, advance: advance} =
      start_gate(burst: 4, rate: 10, player_floor: 0, admin_wait_ms: 500, player_wait_ms: 500)

    for _ <- 1..4, do: Gate.acquire(:admin, g)

    player = Task.async(fn -> {:player, Gate.acquire(:player, g)} end)
    Process.sleep(30)
    admin = Task.async(fn -> {:admin, Gate.acquire(:admin, g)} end)
    Process.sleep(30)

    # one permit becomes available: it goes to the admin, though the player came first
    advance.(100)
    assert Task.await(admin) == {:admin, :ok}
    refute Task.yield(player, 80)
    advance.(100)
    assert Task.await(player) == {:player, :ok}
  end

  test "the breaker refuses requests, fails the waiting ones and can be reset" do
    %{gate: g, advance: advance} = start_gate(burst: 1, admin_wait_ms: 1_000, breaker_ms: 500)
    assert Gate.acquire(:admin, g) == :ok

    waiting = Task.async(fn -> Gate.acquire(:admin, g) end)
    Process.sleep(40)
    assert ExUnit.CaptureLog.capture_log(fn -> Gate.trip(nil, g) end) =~ "blocking us"
    assert Task.await(waiting) == {:error, :blocked}
    assert Gate.acquire(:admin, g) == {:error, :blocked}
    assert Gate.acquire(:player, g) == {:error, :blocked}

    # after the breaker time (and enough time for a permit) it works again
    advance.(600)
    assert Gate.acquire(:admin, g) == :ok
  end

  test "reset closes the breaker" do
    %{gate: g} = start_gate([])
    ExUnit.CaptureLog.capture_log(fn -> Gate.trip(60_000, g) end)
    assert Gate.acquire(:admin, g) == {:error, :blocked}
    Gate.reset(g)
    assert Gate.acquire(:admin, g) == :ok
  end

  test "the cache keeps values until they expire" do
    %{gate: g, advance: advance} = start_gate(cache_ttl_ms: 1_000)
    assert Gate.cache_get(:k, g) == :miss
    Gate.cache_put(:k, [1, 2], g)
    assert Gate.cache_get(:k, g) == {:ok, [1, 2]}
    advance.(999)
    assert Gate.cache_get(:k, g) == {:ok, [1, 2]}
    advance.(2)
    assert Gate.cache_get(:k, g) == :miss
  end

  test "cache_ttl_ms 0 turns the cache off; disabled lets everything through" do
    %{gate: g} = start_gate(cache_ttl_ms: 0, enabled: false, burst: 1)
    Gate.cache_put(:k, 1, g)
    assert Gate.cache_get(:k, g) == :miss
    assert for(_ <- 1..5, do: Gate.acquire(:admin, g)) == List.duplicate(:ok, 5)
  end

  test "the cache is emptied when it is full" do
    %{gate: g} = start_gate(cache_max: 2)
    Gate.cache_put(:a, 1, g)
    Gate.cache_put(:b, 2, g)
    Gate.cache_put(:c, 3, g)
    assert Gate.cache_get(:a, g) == :miss
    assert Gate.cache_get(:c, g) == {:ok, 3}
  end
end
