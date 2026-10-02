defmodule MillenniumQuiz.Cards do
  @moduledoc """
  The card pool: a local copy of every card used in a question, with its
  current name and text in every language and all its printed text versions
  (errata), so the remote sources are only asked once per card.

  Sources (see `MillenniumQuiz.Cards.Sources.*`):
    * YGOPRODeck - search, TCG release date
    * YAML Yugi - names and texts in every language
    * Yugipedia - errata history and release dates of the products
  """

  import Ecto.Query, warn: false

  alias MillenniumQuiz.Repo
  alias MillenniumQuiz.Cards.{Card, CardText, ErrataParser}
  alias MillenniumQuiz.Cards.Sources.{YamlYugi, YGOPRODeck, Yugipedia}

  @min_query_length 3

  def min_query_length, do: @min_query_length

  @doc """
  Searches cards by name that were released in the TCG by the format's date.
  Each result has `:in_pool` set when the card is already stored locally.
  """
  def search(query, %{date: date}) do
    query = String.trim(query)

    if String.length(query) < @min_query_length do
      {:ok, []}
    else
      with {:ok, results} <- YGOPRODeck.search(query, before: date) do
        konami_ids = for %{konami_id: id} when is_integer(id) <- results, do: id

        in_pool =
          Repo.all(from c in Card, where: c.konami_id in ^konami_ids, select: c.konami_id)
          |> MapSet.new()

        {:ok, Enum.map(results, &Map.put(&1, :in_pool, MapSet.member?(in_pool, &1.konami_id)))}
      end
    end
  end

  def get_card!(id), do: Card |> Repo.get!(id) |> Repo.preload(:card_texts)

  @doc "Cards by id with their texts, in the order of `ids`."
  def get_cards(ids) do
    cards =
      Repo.all(from c in Card, where: c.id in ^ids, preload: :card_texts) |> Map.new(&{&1.id, &1})

    for id <- ids, card = cards[id], do: card
  end

  @doc """
  Returns the card for a YGOPRODeck id from the pool, importing it from the
  remote sources first when it isn't stored yet.
  """
  def import(password) when is_integer(password) do
    case Repo.get_by(Card, password: password) do
      %Card{} = card ->
        {:ok, Repo.preload(card, :card_texts)}

      nil ->
        with {:ok, info} <- YGOPRODeck.fetch(password) do
          case info.konami_id && Repo.get_by(Card, konami_id: info.konami_id) do
            %Card{} = card -> {:ok, Repo.preload(card, :card_texts)}
            _ -> fetch_and_store(info, %Card{})
          end
        end
    end
  end

  @doc "Fetches a stored card again from the remote sources, e.g. after new errata."
  def refresh(%Card{} = card) do
    with {:ok, info} <- YGOPRODeck.fetch(card.password) do
      fetch_and_store(info, Repo.preload(card, :card_texts))
    end
  end

  defp fetch_and_store(info, card) do
    with {:ok, yaml} <- YamlYugi.fetch(info.passwords),
         {:ok, versions} <- errata(yaml.yugipedia_page_id),
         sets = for({_, vs} <- versions, %{set: set} when is_binary(set) <- vs, do: set),
         {:ok, dates} <- Yugipedia.release_dates(sets, Map.keys(versions)) do
      texts = card_texts(versions, dates, yaml, info)

      card
      |> Ecto.Changeset.change(
        password: yaml.password,
        konami_id: yaml.konami_id || info.konami_id,
        yugipedia_page_id: yaml.yugipedia_page_id,
        name: yaml.names["en"] || info.name,
        card_type: info.card_type,
        tcg_release_date: info.tcg_release_date,
        names: yaml.names,
        texts: yaml.texts,
        fetched_at: DateTime.utc_now(:second)
      )
      |> Ecto.Changeset.put_assoc(:card_texts, texts)
      |> Repo.insert_or_update()
    end
  end

  defp errata(nil), do: {:ok, %{}}

  defp errata(page_id) do
    case Yugipedia.errata_wikitext(page_id) do
      {:ok, nil} -> {:ok, %{}}
      {:ok, wikitext} -> {:ok, ErrataParser.parse(wikitext)}
      error -> error
    end
  end

  # A card without English errata has had a single English text since its release.
  defp card_texts(versions, dates, yaml, info) do
    versions =
      if Map.has_key?(versions, "en") or is_nil(yaml.texts["en"]),
        do: versions,
        else: Map.put(versions, "en", [%{version: 0, text: yaml.texts["en"], set: nil}])

    for {language, list} <- versions, version <- list do
      released_on =
        get_in(dates, [version.set, language]) ||
          if(language == "en" and is_nil(version.set), do: info.tcg_release_date)

      %CardText{
        language: language,
        version: version.version,
        text: version.text,
        set: version.set,
        released_on: released_on
      }
    end
  end

  @doc """
  The text of a card as it read on `date`, in `language`: returns
  `%{text, set, released_on}`.

  It is the newest printed version released on or before the date. Reprints
  that bring back an older wording (e.g. Legendary Collection reproductions)
  are not errata, so only the first print of each wording counts. Before the
  first dated version it is the oldest one; without versions in the language,
  the current text. A nil date means today.
  """
  def text_on(%Card{} = card, date, language \\ "en") do
    versions =
      card.card_texts
      |> Enum.filter(&(&1.language == language))
      |> Enum.sort_by(& &1.version)
      |> Enum.uniq_by(& &1.text)

    eligible =
      Enum.filter(versions, fn v ->
        v.released_on && (is_nil(date) or Date.compare(v.released_on, date) != :gt)
      end)

    cond do
      eligible != [] ->
        eligible |> Enum.max_by(& &1, &newer?/2) |> as_text()

      versions != [] and date != nil ->
        versions |> hd() |> as_text()

      versions != [] ->
        versions |> List.last() |> as_text()

      true ->
        %{text: card.texts[language] || card.texts["en"], set: nil, released_on: nil}
    end
  end

  defp newer?(a, b) do
    case Date.compare(a.released_on, b.released_on) do
      :eq -> a.version >= b.version
      order -> order == :gt
    end
  end

  defp as_text(%CardText{} = v), do: %{text: v.text, set: v.set, released_on: v.released_on}
end
