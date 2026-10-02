defmodule MillenniumQuiz.Cards.Sources.YGOPRODeck do
  @moduledoc """
  Card search via the YGOPRODeck API (https://ygoprodeck.com/api-guide/).
  Limited to 20 requests per second; going over blocks the IP for an hour,
  so callers debounce and only search with 3+ characters.
  """
  alias MillenniumQuiz.Cards.Sources.HTTP

  @base_url "https://db.ygoprodeck.com/api/v7"

  # `password` is YGOPRODeck's id, sometimes the one of an alternate artwork;
  # `passwords` lists every artwork's id, the printed password among them.
  @type result :: %{
          password: integer(),
          passwords: [integer()],
          konami_id: integer() | nil,
          name: String.t(),
          card_type: String.t(),
          tcg_release_date: Date.t() | nil
        }

  @doc "Cards whose name contains `query`, first released in the TCG by `before`."
  @spec search(String.t(), keyword()) :: {:ok, [result()]} | {:error, term()}
  def search(query, opts \\ []) do
    params =
      [fname: query, misc: "yes", num: 20, offset: 0, sort: "name"] ++
        case opts[:before] do
          nil -> []
          date -> [enddate: Date.to_iso8601(date), dateregion: "tcg"]
        end

    get(params)
  end

  @doc """
  One card by any of its ids. Asked by id, the API only lists that one
  artwork, so the card is loaded again by its exact name to get them all.
  """
  @spec fetch(integer()) :: {:ok, result()} | {:error, term()}
  def fetch(password) do
    with {:ok, [card]} <- get(id: password, misc: "yes"),
         {:ok, [full]} <- get(name: card.name, misc: "yes") do
      {:ok, full}
    else
      {:ok, _} -> {:error, :not_found}
      error -> error
    end
  end

  defp get(params) do
    case Req.get(HTTP.new(@base_url), url: "/cardinfo.php", params: params) do
      {:ok, %{status: 200, body: %{"data" => cards}}} -> {:ok, Enum.map(cards, &result/1)}
      # "No card matching your query was found in the database."
      {:ok, %{status: 400}} -> {:ok, []}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp result(card) do
    misc = card |> Map.get("misc_info", [%{}]) |> List.first(%{})

    %{
      password: card["id"],
      passwords: Enum.uniq([card["id"] | Enum.map(card["card_images"] || [], & &1["id"])]),
      konami_id: misc["konami_id"],
      name: card["name"],
      card_type: card["humanReadableCardType"] || card["type"],
      tcg_release_date: date(misc["tcg_date"])
    }
  end

  defp date(nil), do: nil

  defp date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
