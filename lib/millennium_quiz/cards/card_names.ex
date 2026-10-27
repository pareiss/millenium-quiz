defmodule MillenniumQuiz.Cards.CardNames do
  @moduledoc """
  The list of all card names released in the TCG, kept in the `card_names`
  table so that the card search does not ask YGOPRODeck for every name that is
  typed (`Cards.search/3` looks here first and only asks when nothing matches).

  `refresh/1` fills it from YGOPRODeck, one request per release year: the
  whole list in one answer is 25 MB, a year about 1 to 2 MB, so a small server
  can parse it. Every request goes through the gate.

  `CardNames.Refresher` runs it inside the application: when the list is empty
  (first start after the table was added) and then every week. Rows are
  upserted by password; after a refresh that went through, the rows it did not
  see again (a card whose listed id changed, a card taken off the list) are
  deleted. `Release.refresh_card_names/0` does the same from a release `eval`,
  for a host where the application cannot do it.
  """
  import Ecto.Query

  alias MillenniumQuiz.Cards.{CardName, NameMatch}
  alias MillenniumQuiz.Cards.Sources.YGOPRODeck
  alias MillenniumQuiz.Repo

  @limit 20
  @chunk 500

  @doc """
  Cards of the list whose name contains `query`, released by `before` (a
  `Date`; a card without a release date does not count as released). The maps
  look like the answers of `YGOPRODeck.search/2`. At most #{@limit}; the
  caller makes sure the query is long enough.
  """
  def search(query, %Date{} = before) when is_binary(query) do
    Repo.all(
      from c in NameMatch.matching(CardName, query),
        where: c.tcg_release_date <= ^before,
        limit: @limit,
        select: %{
          password: c.password,
          passwords: c.passwords,
          konami_id: c.konami_id,
          name: c.name,
          card_type: c.card_type,
          frame_type: c.frame_type,
          tcg_release_date: c.tcg_release_date
        }
    )
  end

  @doc "How many names the list holds."
  def count, do: Repo.aggregate(CardName, :count)

  @doc "When the list was last written to, or `nil` while it is empty."
  def refreshed_at, do: Repo.aggregate(CardName, :max, :updated_at)

  @doc """
  The windows `refresh/1` asks for: everything up to the end of 2002, then one
  per year, the last one open-ended (cards announced for later).
  """
  def windows(%Date{year: this_year}) do
    [{~D[1990-01-01], ~D[2002-12-31]}] ++
      for(year <- 2003..this_year, do: {Date.new!(year, 1, 1), Date.new!(year, 12, 31)}) ++
      [{Date.new!(this_year + 1, 1, 1), ~D[2099-12-31]}]
  end

  @doc """
  Whether the list is empty or was last written more than `max_age_days` ago.
  """
  def stale?(max_age_days, now \\ DateTime.utc_now()) do
    case refreshed_at() do
      nil -> true
      at -> DateTime.diff(now, at, :day) >= max_age_days
    end
  end

  @doc """
  Fetches the names and stores them. Options: `:today` (a `Date`, for tests)
  and `:gate`. Returns `{:ok, count}`, the number of names written, or
  `{:error, reason, fetched}` when a request failed, with the number of names
  fetched before it.

  All the windows are fetched first and written in one transaction, so a
  failed refresh writes nothing: the list stays as it was, and as stale as it
  was, which is what makes `Refresher` try again at its next check (a list
  half filled by a failed first run would count as fresh, and would hide the
  newer cards from the search, which only asks YGOPRODeck when nothing matches).
  The results held at once are the compact maps, not the raw answers.

  After a refresh that went through, rows it did not write are deleted, but
  only when it wrote at least 90% as many names as the list held: an answer
  that came back empty by mistake must not empty the list.
  """
  def refresh(opts \\ []) do
    today = Keyword.get(opts, :today, Date.utc_today())

    fetched =
      Enum.reduce_while(windows(today), {:ok, []}, fn {first, last}, {:ok, acc} ->
        case YGOPRODeck.released_between(first, last, Keyword.take(opts, [:gate])) do
          {:ok, results} -> {:cont, {:ok, [results | acc]}}
          {:error, reason} -> {:halt, {:error, reason, acc |> List.flatten() |> length()}}
        end
      end)

    with {:ok, windows} <- fetched,
         do: Repo.transaction(fn -> replace(windows) end, timeout: :timer.minutes(2))
  end

  defp replace(windows) do
    started = DateTime.utc_now(:second)
    before_count = count()
    written = windows |> Enum.reverse() |> Enum.map(&store/1) |> Enum.sum()

    if written >= before_count * 0.9 do
      Repo.delete_all(from c in CardName, where: c.updated_at < ^started)
    end

    written
  end

  defp store(results) do
    now = DateTime.utc_now(:second)

    results
    |> Enum.uniq_by(& &1.password)
    |> Enum.chunk_every(@chunk)
    |> Enum.map(fn chunk ->
      rows =
        Enum.map(chunk, fn r ->
          r
          |> Map.take([
            :password,
            :passwords,
            :konami_id,
            :name,
            :card_type,
            :frame_type,
            :tcg_release_date
          ])
          |> Map.merge(%{inserted_at: now, updated_at: now})
        end)

      {n, _} =
        Repo.insert_all(CardName, rows,
          on_conflict: {:replace_all_except, [:id, :inserted_at]},
          conflict_target: :password
        )

      n
    end)
    |> Enum.sum()
  end
end
