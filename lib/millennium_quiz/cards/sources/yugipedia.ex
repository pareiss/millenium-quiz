defmodule MillenniumQuiz.Cards.Sources.Yugipedia do
  @moduledoc """
  Errata history and set release dates from Yugipedia's MediaWiki API
  (https://yugipedia.com/api.php). Text on Yugipedia is CC BY-SA 4.0.
  """
  alias MillenniumQuiz.Cards.Sources.HTTP

  @base_url "https://yugipedia.com/api.php"

  # Semantic MediaWiki release date properties per card pool language, in
  # order of preference. English follows the TCG (North American) timeline.
  @date_properties %{
    "en" => ["North American English release date", "English release date"],
    "de" => ["German release date"],
    "fr" => ["French release date"],
    "it" => ["Italian release date"],
    "es" => ["Spanish release date"],
    "pt" => ["Portuguese release date"],
    "ja" => ["Japanese release date"],
    "ko" => ["Korean release date"],
    "zh-CN" => ["Simplified Chinese release date"],
    "zh-TW" => ["Traditional Chinese release date"]
  }

  @doc "Wikitext of the `Card Errata:` page of a card, or nil when it has none."
  def errata_wikitext(page_id) do
    with {:ok, %{"query" => %{"pages" => [page]}}} <-
           api(action: "query", pageids: page_id) do
      case page do
        %{"missing" => true} ->
          {:error, :not_found}

        %{"title" => title} ->
          case api(action: "parse", page: "Card Errata:" <> title, prop: "wikitext") do
            {:ok, %{"parse" => %{"wikitext" => wikitext}}} -> {:ok, wikitext}
            {:ok, %{"error" => %{"code" => "missingtitle"}}} -> {:ok, nil}
            {:ok, other} -> {:error, {:unexpected, other}}
            error -> error
          end
      end
    end
  end

  @doc """
  Release dates of products: `%{set_name => %{language => Date}}`, only for
  the given languages. Partial dates ("2003-09") count from the 1st.
  """
  def release_dates([], _languages), do: {:ok, %{}}

  def release_dates(set_names, languages) do
    properties = Map.take(@date_properties, languages)
    printouts = properties |> Map.values() |> List.flatten() |> Enum.map_join(&"|?#{&1}")

    set_names
    |> Enum.uniq()
    |> Enum.chunk_every(25)
    |> Enum.reduce_while({:ok, %{}}, fn chunk, {:ok, acc} ->
      query = "[[#{Enum.join(chunk, "||")}]]#{printouts}|limit=50"

      case api(action: "ask", query: query) do
        {:ok, %{"query" => %{"results" => results}}} ->
          {:cont, {:ok, Map.merge(acc, dates(results, properties))}}

        {:ok, other} ->
          {:halt, {:error, {:unexpected, other}}}

        error ->
          {:halt, error}
      end
    end)
  end

  # An empty result set is serialized as [] instead of {}.
  defp dates([], _properties), do: %{}

  defp dates(results, properties) do
    Map.new(results, fn {set, %{"printouts" => printouts}} ->
      {set,
       properties
       |> Enum.flat_map(fn {lang, names} ->
         case Enum.find_value(names, &first_date(printouts[&1])) do
           nil -> []
           date -> [{lang, date}]
         end
       end)
       |> Map.new()}
    end)
  end

  defp first_date([%{"raw" => raw} | _]), do: parse_raw_date(raw)
  defp first_date(_), do: nil

  # SMW raw dates look like "1/2002/3/8", "1/2003/9" or "1/2003".
  @doc false
  def parse_raw_date(raw) do
    case raw |> String.split("/") |> Enum.drop(1) |> Enum.map(&Integer.parse/1) do
      [{y, _}, {m, _}, {d, _}] -> Date.new(y, m, d) |> ok_or_nil()
      [{y, _}, {m, _}] -> Date.new(y, m, 1) |> ok_or_nil()
      [{y, _}] -> Date.new(y, 1, 1) |> ok_or_nil()
      _ -> nil
    end
  end

  defp ok_or_nil({:ok, date}), do: date
  defp ok_or_nil(_), do: nil

  defp api(params) do
    case Req.get(HTTP.new(@base_url), params: [format: "json", formatversion: 2] ++ params) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
