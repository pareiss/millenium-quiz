defmodule MillenniumQuiz.Cards.ErrataParser do
  @moduledoc """
  Turns the wikitext of a Yugipedia `Card Errata:<card>` page into the text
  versions of a card, per language.

  Every `{{Errata table}}` lists the printed versions of a card in order
  (`lore0`, `lore1`, ...). Each `loreN` is the *complete* text of that
  version; the markup is only annotation (`<ins>` = new since the previous
  version, `<del>` = removed in the next one), so it is dropped and all words
  are kept. A version without `lore` only changed something else (card type,
  name) and keeps the text of its neighbour. `capN` names the product the
  version was first printed in: its last wiki link.
  """

  # Yugipedia language codes that differ from the ones used in the card pool.
  @languages %{"sc" => "zh-CN", "tc" => "zh-TW"}

  @type version :: %{version: non_neg_integer(), text: String.t(), set: String.t() | nil}

  @doc "Returns `%{language => [version]}`; languages without any text are left out."
  @spec parse(String.t()) :: %{String.t() => [version()]}
  def parse(wikitext) when is_binary(wikitext) do
    ~r/\{\{Errata table(\|lang=(\w+))?\s*\n(.*?)\n\}\}/s
    |> Regex.scan(wikitext, capture: :all_but_first)
    |> Enum.map(fn [_, lang, body] -> {language(lang), versions(body)} end)
    |> Enum.reject(fn {_, versions} -> versions == [] end)
    |> Map.new()
  end

  defp language(""), do: "en"
  defp language(lang), do: Map.get(@languages, lang, lang)

  defp versions(body) do
    params =
      ~r/^\|\s*([a-z_]+?)(\d+)\s*=\s*(.*)$/m
      |> Regex.scan(body, capture: :all_but_first)
      |> Enum.reduce(%{}, fn [key, index, value], acc ->
        Map.update(acc, String.to_integer(index), %{key => value}, &Map.put(&1, key, value))
      end)

    indexes = params |> Map.keys() |> Enum.sort()
    texts = Enum.map(indexes, &(params[&1]["lore"] && clean(params[&1]["lore"])))

    if Enum.all?(texts, &is_nil/1) do
      []
    else
      texts = fill_gaps(texts)

      indexes
      |> Enum.zip(texts)
      |> Enum.map(fn {index, text} ->
        %{version: index, text: text, set: set_name(params[index]["cap"])}
      end)
    end
  end

  # Missing texts repeat the previous version; leading ones the first known.
  defp fill_gaps(texts) do
    first = Enum.find(texts, & &1)

    texts
    |> Enum.map_reduce(first, fn text, previous -> {text || previous, text || previous} end)
    |> elem(0)
  end

  defp set_name(nil), do: nil

  defp set_name(caption) do
    case Regex.scan(~r/\[\[([^\]|]+)(?:\|[^\]]*)?\]\]/, caption, capture: :all_but_first) do
      [] -> nil
      links -> links |> List.last() |> hd() |> String.trim()
    end
  end

  @doc "Removes wiki and HTML markup from a text, keeping its words."
  def clean(text) do
    text
    # old Japanese prints list ATK/DEF below a rule; that is not card text
    |> String.replace(~r/<hr[^>]*>.*$/s, "")
    |> String.replace(~r/<br\s*\/?>/, "\n")
    |> String.replace(~r/\{\{Ruby\|([^|}]*)\|[^}]*\}\}/, "\\1")
    |> String.replace(~r/\[\[(?:[^\]|]*\|)?([^\]]*)\]\]/, "\\1")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/'{2,}/, "")
    |> String.replace("&nbsp;", " ")
    |> String.split("\n")
    |> Enum.map_join("\n", &String.trim/1)
    |> String.trim()
  end
end
