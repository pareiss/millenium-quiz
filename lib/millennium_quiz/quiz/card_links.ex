defmodule MillenniumQuiz.Quiz.CardLinks do
  @moduledoc """
  The `[Card Name]` markup of question texts. Pure: no database.

  ## Syntax

  A link is `[`, one or more characters that are neither `[` nor `]`, and `]`.
  There is no nesting. Surrounding spaces inside the brackets are ignored when
  matching (`[ Dark Hole ]` is `Dark Hole`).

    * In `parse/2` a link only counts when its name equals (case-insensitive)
      the name of one of the question's cards. Any other `[..]` stays plain text
      with its brackets, so ordinary prose such as "[sic]" is unharmed. With
      duplicate names the first card wins.
    * An unclosed `[` ("[Dark Hole"), an empty `[]` and a `[` inside a name
      ("[a [Dark Hole]") are no link by themselves: the first two stay text,
      and in the third only the inner `[Dark Hole]` can be a link (a name never
      contains a bracket).

  ## Escaping

  There is no escape syntax. A literal bracket pair that happens to equal one
  of the question's card names is a link; that is accepted. An admin who does
  not want it uses `unlink/2`.
  """

  @link ~r/\[([^\[\]]+)\]/u

  @type card :: %{required(:name) => String.t(), optional(any) => any}
  @type segment :: {:text, String.t()} | {:card, String.t(), non_neg_integer}

  @doc """
  Splits `text` into segments. `cards` is the question's cards in order.
  `{:card, name, index}` carries the name as written in the text (trimmed) and
  the position of the card in `cards`. Adjacent text is merged and empty text
  is never returned.
  """
  @spec parse(String.t() | nil, [card]) :: [segment]
  def parse(nil, _cards), do: []

  def parse(text, cards) when is_binary(text) do
    index =
      cards
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {card, i}, acc -> Map.put_new(acc, key(card.name), i) end)

    @link
    |> Regex.split(text, include_captures: true)
    |> Enum.flat_map(fn part ->
      with [_, name] <- Regex.run(@link, part),
           name = String.trim(name),
           i when is_integer(i) <- Map.get(index, key(name)) do
        [{:card, name, i}]
      else
        _ -> [{:text, part}]
      end
    end)
    |> merge_text()
  end

  @doc "The distinct bracketed names of `text`, trimmed, in order of first use."
  @spec names(String.t() | nil) :: [String.t()]
  def names(nil), do: []

  def names(text) when is_binary(text) do
    @link
    |> Regex.scan(text, capture: :all_but_first)
    |> Enum.map(fn [name] -> String.trim(name) end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq_by(&key/1)
  end

  @doc """
  Removes the brackets of every `[name]` (case-insensitive, spaces inside the
  brackets ignored), keeping the text as written. Other brackets are untouched.
  """
  @spec unlink(String.t() | nil, String.t()) :: String.t()
  def unlink(nil, _name), do: ""

  def unlink(text, name) when is_binary(text) do
    wanted = key(name)

    Regex.replace(@link, text, fn whole, inner ->
      if key(inner) == wanted, do: inner, else: whole
    end)
  end

  @doc """
  The text with every link replaced by its name. Used where the cards are not
  at hand (truncated texts in admin lists and delete dialogs), so there any
  `[non-empty text without brackets]` is treated as a link, whether or not a
  card of that name exists.
  """
  @spec plain(String.t() | nil) :: String.t()
  def plain(nil), do: ""

  def plain(text) when is_binary(text) do
    Regex.replace(@link, text, fn _whole, inner ->
      if String.trim(inner) == "", do: "[" <> inner <> "]", else: String.trim(inner)
    end)
  end

  defp key(name), do: name |> String.trim() |> String.downcase()

  defp merge_text(segments) do
    segments
    |> Enum.reduce([], fn
      {:text, ""}, acc -> acc
      {:text, t}, [{:text, prev} | rest] -> [{:text, prev <> t} | rest]
      segment, acc -> [segment | acc]
    end)
    |> Enum.reverse()
  end
end
