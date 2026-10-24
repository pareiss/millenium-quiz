defmodule MillenniumQuiz.Cards.ArtworkCacheTest do
  use ExUnit.Case, async: true

  alias MillenniumQuiz.Cards.ArtworkCache

  defp start_cache(opts) do
    name = :"cache_#{System.unique_integer([:positive])}"
    start_supervised!({ArtworkCache, [name: name] ++ opts})
    name
  end

  # the cache is filled by a cast: wait until it has handled it
  defp sync(cache), do: ArtworkCache.stats(cache)

  test "a hit returns the same bytes without computing again" do
    cache = start_cache([])
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    fun = fn ->
      Agent.update(counter, &(&1 + 1))
      {:ok, "resized"}
    end

    assert ArtworkCache.fetch(cache, {1, 2, 3, 200}, fun) == {:ok, "resized"}
    sync(cache)
    assert ArtworkCache.fetch(cache, {1, 2, 3, 200}, fun) == {:ok, "resized"}
    assert Agent.get(counter, & &1) == 1

    # another width or a re-fetched artwork is another key
    assert ArtworkCache.fetch(cache, {1, 2, 3, 400}, fun) == {:ok, "resized"}
    assert ArtworkCache.fetch(cache, {1, 2, 4, 200}, fun) == {:ok, "resized"}
    assert Agent.get(counter, & &1) == 3
  end

  test "failures are not cached" do
    cache = start_cache([])
    assert ArtworkCache.fetch(cache, :a, fn -> {:error, :boom} end) == {:error, :boom}
    sync(cache)
    assert ArtworkCache.fetch(cache, :a, fn -> {:ok, "fine"} end) == {:ok, "fine"}
  end

  test "the entry bound holds and the oldest entries go first" do
    cache = start_cache(max_entries: 3)

    for i <- 1..5, do: ArtworkCache.fetch(cache, i, fn -> {:ok, "x#{i}"} end)

    assert %{entries: 3} = sync(cache)
    assert ArtworkCache.fetch(cache, 1, fn -> {:ok, :recomputed} end) == {:ok, :recomputed}
    assert ArtworkCache.fetch(cache, 5, fn -> flunk("5 should be cached") end) == {:ok, "x5"}
  end

  test "the byte bound holds" do
    cache = start_cache(max_bytes: 10)

    for i <- 1..6, do: ArtworkCache.fetch(cache, i, fn -> {:ok, "1234"} end)
    assert %{entries: 2, bytes: 8} = sync(cache)

    # larger than the whole cache: served, not stored
    assert ArtworkCache.fetch(cache, :big, fn -> {:ok, String.duplicate("x", 11)} end) ==
             {:ok, String.duplicate("x", 11)}

    assert %{entries: 2} = sync(cache)
  end
end
