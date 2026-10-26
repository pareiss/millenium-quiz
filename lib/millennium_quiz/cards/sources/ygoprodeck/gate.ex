defmodule MillenniumQuiz.Cards.Sources.YGOPRODeck.Gate do
  @moduledoc """
  The one door to the YGOPRODeck API for the whole node, so that admins and
  players together stay under its cap (20 requests per second; going over
  blocks the server's IP for an hour, which would stop admin imports too).

  Every API request first calls `acquire/2`; the request itself then runs in
  the caller's process. The gate hands out permits from a token bucket and
  keeps three protections:

    * **Priorities.** `:admin` requests are served first and may use the whole
      bucket. `:player` requests only get a permit while the bucket is more
      than `player_floor` full, wait in a short queue and are dropped
      (`{:error, :busy}`) when the queue is full or they waited more than
      `player_wait_ms`. A flood of players therefore cannot starve an admin.
    * **Circuit breaker.** `trip/2` (called when the API answers 429 or 403)
      refuses every request with `{:error, :blocked}` for `breaker_ms` and
      fails the ones waiting.
    * **Cache.** `cache_get/2` and `cache_put/3` keep search results for
      `cache_ttl_ms` in a table owned by the gate; most traffic is the same
      few names typed again.

  The bucket is per node. With several nodes divide `rate` and `burst` by the
  node count (or register the gate globally).

  ## Configuration

      config :millennium_quiz, MillenniumQuiz.Cards.Sources.YGOPRODeck.Gate,
        rate: 8, burst: 8

  `enabled: false` lets every request through (the test suite does this);
  `cache_ttl_ms: 0` turns the cache off. See `defaults/0` for all options.
  """
  use GenServer

  require Logger

  @type priority :: :admin | :player

  @defaults [
    enabled: true,
    # permits per second and the most that can be saved up: well under the cap
    rate: 8,
    burst: 8,
    # a player only gets a permit while more than this share of the bucket is full
    player_floor: 0.5,
    admin_queue: 50,
    admin_wait_ms: 10_000,
    player_queue: 10,
    player_wait_ms: 1_500,
    breaker_ms: :timer.minutes(5),
    cache_ttl_ms: :timer.hours(24),
    cache_max: 5_000,
    clock: &System.monotonic_time/1
  ]

  @tick_ms 25
  @sweep_ms :timer.minutes(10)

  def defaults, do: @defaults

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Asks for a permit to make one API request. Returns `:ok`,
  `{:error, :busy}` (queue full or waited too long) or `{:error, :blocked}`
  (the breaker is open).
  """
  @spec acquire(priority, atom) :: :ok | {:error, :busy | :blocked}
  def acquire(priority, server \\ __MODULE__) when priority in [:admin, :player] do
    if config(server, :enabled) == false do
      :ok
    else
      GenServer.call(server, {:acquire, priority}, config(server, wait_key(priority)) + 5_000)
    end
  end

  @doc "Opens the breaker: no request is made for `ms` (default `breaker_ms`)."
  def trip(ms \\ nil, server \\ __MODULE__), do: GenServer.call(server, {:trip, ms})

  @doc "Closes the breaker again (for tests and operators)."
  def reset(server \\ __MODULE__), do: GenServer.call(server, :reset)

  @doc "A cached value as `{:ok, value}`, or `:miss`."
  def cache_get(key, server \\ __MODULE__) do
    with true <- config(server, :cache_ttl_ms) > 0,
         [{^key, expires, value}] <- :ets.lookup(table_name(server), key),
         true <- expires > now_ms(server) do
      {:ok, value}
    else
      _ -> :miss
    end
  rescue
    ArgumentError -> :miss
  end

  def cache_put(key, value, server \\ __MODULE__) do
    ttl = config(server, :cache_ttl_ms)

    if ttl > 0 do
      table = table_name(server)
      if :ets.info(table, :size) >= config(server, :cache_max), do: :ets.delete_all_objects(table)
      :ets.insert(table, {key, now_ms(server) + ttl, value})
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  ## Server

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    config = effective_config(Keyword.delete(opts, :name))

    :ets.new(table_name(name), [:set, :public, :named_table, read_concurrency: true])
    :persistent_term.put({__MODULE__, name}, config)
    Process.send_after(self(), :sweep, @sweep_ms)

    {:ok,
     %{
       config: config,
       table: table_name(name),
       tokens: config[:burst] * 1.0,
       at: config[:clock].(:millisecond),
       breaker_until: nil,
       admin: :queue.new(),
       player: :queue.new(),
       ticking: false
     }}
  end

  @impl true
  def handle_call({:acquire, priority}, from, state) do
    state = refill(state)

    cond do
      blocked?(state) ->
        {:reply, {:error, :blocked}, state}

      queue_empty?(state, priority) and permit?(state, priority) ->
        {:reply, :ok, take(state)}

      :queue.len(state[priority]) >= state.config[queue_key(priority)] ->
        {:reply, {:error, :busy}, state}

      true ->
        deadline = now(state) + state.config[wait_key(priority)]
        queue = :queue.in({from, deadline}, state[priority])
        {:noreply, state |> Map.put(priority, queue) |> ensure_tick()}
    end
  end

  def handle_call({:trip, ms}, _from, state) do
    ms = ms || state.config[:breaker_ms]
    Logger.warning("YGOPRODeck looks like it is blocking us: no requests for #{div(ms, 1000)} s")
    state = %{state | breaker_until: now(state) + ms}
    {:reply, :ok, fail_all(state, {:error, :blocked})}
  end

  def handle_call(:reset, _from, state), do: {:reply, :ok, %{state | breaker_until: nil}}

  @impl true
  def handle_info(:tick, state) do
    state = state |> Map.put(:ticking, false) |> refill() |> expire() |> drain()
    {:noreply, ensure_tick(state)}
  end

  def handle_info(:sweep, state) do
    :ets.select_delete(state.table, [{{:_, :"$1", :_}, [{:<, :"$1", now(state)}], [true]}])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  # Admins first, then players while the bucket is above the floor.
  defp drain(state) do
    cond do
      blocked?(state) ->
        fail_all(state, {:error, :blocked})

      not :queue.is_empty(state.admin) and permit?(state, :admin) ->
        state |> pop(:admin) |> drain()

      :queue.is_empty(state.admin) and not :queue.is_empty(state.player) and
          permit?(state, :player) ->
        state |> pop(:player) |> drain()

      true ->
        state
    end
  end

  defp pop(state, priority) do
    {{:value, {from, _deadline}}, rest} = :queue.out(state[priority])
    GenServer.reply(from, :ok)
    state |> Map.put(priority, rest) |> take()
  end

  # Waiters past their deadline are told it is busy.
  defp expire(state) do
    now = now(state)

    Enum.reduce([:admin, :player], state, fn priority, state ->
      {late, keep} =
        state[priority]
        |> :queue.to_list()
        |> Enum.split_with(fn {_, deadline} -> deadline <= now end)

      Enum.each(late, fn {from, _} -> GenServer.reply(from, {:error, :busy}) end)
      Map.put(state, priority, :queue.from_list(keep))
    end)
  end

  defp fail_all(state, reply) do
    for priority <- [:admin, :player], {from, _} <- :queue.to_list(state[priority]) do
      GenServer.reply(from, reply)
    end

    %{state | admin: :queue.new(), player: :queue.new()}
  end

  defp ensure_tick(%{ticking: true} = state), do: state

  defp ensure_tick(state) do
    if :queue.is_empty(state.admin) and :queue.is_empty(state.player) do
      state
    else
      Process.send_after(self(), :tick, @tick_ms)
      %{state | ticking: true}
    end
  end

  defp refill(state) do
    now = now(state)
    gained = (now - state.at) * state.config[:rate] / 1000
    %{state | tokens: min(state.config[:burst] * 1.0, state.tokens + gained), at: now}
  end

  defp permit?(state, :admin), do: state.tokens >= 1

  defp permit?(state, :player),
    do: state.tokens - 1 >= state.config[:burst] * state.config[:player_floor]

  defp take(state), do: %{state | tokens: state.tokens - 1}

  defp blocked?(%{breaker_until: nil}), do: false
  defp blocked?(state), do: state.breaker_until > now(state)

  defp queue_empty?(state, :admin), do: :queue.is_empty(state.admin)

  # a player does not overtake anybody waiting
  defp queue_empty?(state, :player),
    do: :queue.is_empty(state.admin) and :queue.is_empty(state.player)

  defp now(state), do: state.config[:clock].(:millisecond)

  defp wait_key(:admin), do: :admin_wait_ms
  defp wait_key(:player), do: :player_wait_ms
  defp queue_key(:admin), do: :admin_queue
  defp queue_key(:player), do: :player_queue

  ## Read by the callers without asking the process

  defp effective_config(overrides) do
    @defaults
    |> Keyword.merge(Application.get_env(:millennium_quiz, __MODULE__, []))
    |> Keyword.merge(overrides)
  end

  defp config(server, key) do
    case :persistent_term.get({__MODULE__, server}, nil) do
      nil -> effective_config([])[key]
      config -> config[key]
    end
  end

  defp now_ms(server), do: config(server, :clock).(:millisecond)
  defp table_name(server), do: :"#{server}.cache"
end
