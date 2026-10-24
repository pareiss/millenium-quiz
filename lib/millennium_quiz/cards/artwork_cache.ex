defmodule MillenniumQuiz.Cards.ArtworkCache do
  @moduledoc """
  A small in-memory cache for resized card artworks.

  Keys carry the artwork's identity (`{card_id, artwork_id, fetched_at, width}`),
  so an artwork that is fetched again simply misses and its old renditions age
  out. The cache is bounded by entry count and by bytes; when a bound is
  exceeded the oldest entries go first. Reads go straight to ETS; only inserts
  pass through the process, which keeps the bounds exact.
  """
  use GenServer

  @table __MODULE__
  @max_entries 300
  @max_bytes 32 * 1024 * 1024

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  The cached value for `key`, or the result of `fun` stored under it: `{:ok,
  binary}` or `{:ok, :original}` (a remembered "serve the original" for an
  artwork that can't be resized); anything else isn't cached. `fun` runs in
  the caller.
  """
  def fetch(server \\ __MODULE__, key, fun) do
    table = table(server)

    case lookup(table, key) do
      {:ok, _} = hit ->
        hit

      :error ->
        with {:ok, data} when is_binary(data) or data == :original <- fun.() do
          GenServer.cast(server, {:put, key, data})
          {:ok, data}
        end
    end
  end

  @doc "Entries and bytes currently held."
  def stats(server \\ __MODULE__), do: GenServer.call(server, :stats)

  defp table(__MODULE__), do: @table
  defp table(server), do: GenServer.call(server, :table)

  defp lookup(table, key) do
    case :ets.lookup(table, key) do
      [{^key, data, _seq}] -> {:ok, data}
      [] -> :error
    end
  rescue
    # the cache isn't running (or is restarting): behave as a miss
    ArgumentError -> :error
  end

  @impl true
  def init(opts) do
    options = [:set, :protected, read_concurrency: true]

    # the default instance has a named table; others (tests) an anonymous one
    table =
      if Keyword.get(opts, :name, __MODULE__) == __MODULE__,
        do: :ets.new(@table, [:named_table | options]),
        else: :ets.new(:artwork_cache, options)

    {:ok,
     %{
       table: table,
       order: :queue.new(),
       bytes: 0,
       seq: 0,
       max_entries: Keyword.get(opts, :max_entries, @max_entries),
       max_bytes: Keyword.get(opts, :max_bytes, @max_bytes)
     }}
  end

  @impl true
  def handle_call(:table, _from, state), do: {:reply, state.table, state}

  def handle_call(:stats, _from, state),
    do: {:reply, %{entries: :ets.info(state.table, :size), bytes: state.bytes}, state}

  @impl true
  def handle_cast({:put, key, data}, state) do
    size = size(data)

    if :ets.member(state.table, key) or size > state.max_bytes do
      {:noreply, state}
    else
      seq = state.seq + 1
      :ets.insert(state.table, {key, data, seq})

      state = %{
        state
        | seq: seq,
          bytes: state.bytes + size,
          order: :queue.in({key, size}, state.order)
      }

      {:noreply, evict(state)}
    end
  end

  defp size(data) when is_binary(data), do: byte_size(data)
  defp size(:original), do: 0

  defp evict(state) do
    if :ets.info(state.table, :size) > state.max_entries or state.bytes > state.max_bytes do
      {{:value, {key, size}}, order} = :queue.out(state.order)
      :ets.delete(state.table, key)
      evict(%{state | order: order, bytes: state.bytes - size})
    else
      state
    end
  end
end
