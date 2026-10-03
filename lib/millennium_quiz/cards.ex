defmodule MillenniumQuiz.Cards do
  @moduledoc """
  The card pool: a local copy of every card used in a question, with its
  current name and text in every language and all its printed text versions
  (errata), so the remote sources are only asked once per card.

  Besides the text it keeps everything else printed on the card (stats,
  Spell/Trap property, frame, Pendulum Effect) and the artwork, so cards can
  be drawn locally with the text of any format's date.

  Sources (see `MillenniumQuiz.Cards.Sources.*`):
    * YGOPRODeck - search, TCG release date, frame, artwork
    * YAML Yugi - names, texts, stats and Pendulum Effects in every language
    * Yugipedia - errata history and release dates of the products
  """

  import Ecto.Query, warn: false
  require Logger

  alias MillenniumQuiz.Repo
  alias MillenniumQuiz.Cards.{Card, CardArtwork, CardText, ErrataParser}
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
      fetch_and_store(info, Repo.preload(card, [:card_texts, :artwork]))
    end
  end

  @doc """
  Refreshes every card in the pool, one after the other (the sources are
  rate limited). Returns `{refreshed, failed_card_names}`.
  """
  def refresh_all do
    Repo.all(from c in Card, order_by: c.id)
    |> Enum.reduce({0, []}, fn card, {ok, failed} ->
      case refresh(card) do
        {:ok, _} -> {ok + 1, failed}
        {:error, _} -> {ok, failed ++ [card.name]}
      end
    end)
  end

  @doc "The stored artwork of a card, or nil."
  def get_artwork(card_id), do: Repo.get_by(CardArtwork, card_id: card_id)

  defp fetch_and_store(info, card) do
    with {:ok, yaml} <- YamlYugi.fetch(info.passwords),
         {:ok, versions} <- errata(yaml.yugipedia_page_id),
         sets = for({_, vs} <- versions, %{set: set} when is_binary(set) <- vs, do: set),
         {:ok, dates} <- Yugipedia.release_dates(sets, Map.keys(versions)) do
      texts = card_texts(versions, dates, yaml, info)

      card
      |> Ecto.Changeset.change(yaml.details)
      |> Ecto.Changeset.change(frame_type: info.frame_type)
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
      |> Ecto.Changeset.unique_constraint(:password)
      |> Ecto.Changeset.unique_constraint(:konami_id)
      |> put_artwork(info, yaml.password)
      |> Repo.insert_or_update()
      |> existing_on_conflict(yaml)
      |> case do
        {:ok, card} -> {:ok, %{card | artwork: %Ecto.Association.NotLoaded{}}}
        error -> error
      end
    end
  end

  # The artwork of the printed password; a failed download doesn't stop the
  # import (the card can be refreshed later).
  defp put_artwork(changeset, info, password) do
    artwork_id = if password in info.passwords, do: password, else: hd(info.passwords)

    case YGOPRODeck.artwork(artwork_id) do
      {:ok, artwork} ->
        Ecto.Changeset.put_assoc(
          changeset,
          :artwork,
          struct(CardArtwork, Map.put(artwork, :fetched_at, DateTime.utc_now(:second)))
        )

      {:error, reason} ->
        Logger.warning("No artwork for card #{artwork_id}: #{inspect(reason)}")
        changeset
    end
  end

  # Two imports of the same card can race, and the printed password can
  # already be stored even though the requested id and Konami id were not
  # found. Importing is idempotent, so the stored card is the answer.
  defp existing_on_conflict({:error, %Ecto.Changeset{errors: errors}} = error, yaml) do
    if Keyword.has_key?(errors, :password) or Keyword.has_key?(errors, :konami_id) do
      case Repo.get_by(Card, password: yaml.password) ||
             (yaml.konami_id && Repo.get_by(Card, konami_id: yaml.konami_id)) do
        %Card{} = card -> {:ok, Repo.preload(card, :card_texts)}
        _ -> error
      end
    else
      error
    end
  end

  defp existing_on_conflict(result, _yaml), do: result

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
  first dated version it is the oldest one. If no version of the language has
  a release date, it is the newest wording with `released_on: nil`, so callers
  can tell the date is unknown. Without versions in the language, the current
  text. A nil date means today.
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

      # Without any dates the oldest wording is not a better guess than the
      # newest; return the newest, undated.
      versions != [] and Enum.all?(versions, &is_nil(&1.released_on)) ->
        versions |> List.last() |> as_text()

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
