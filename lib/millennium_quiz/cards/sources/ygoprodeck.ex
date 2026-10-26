defmodule MillenniumQuiz.Cards.Sources.YGOPRODeck do
  @moduledoc """
  Card search via the YGOPRODeck API (https://ygoprodeck.com/api-guide/).
  Limited to 20 requests per second; going over blocks the IP for an hour,
  so callers debounce and only search with 3+ characters, and every request to
  the API goes through `YGOPRODeck.Gate` (shared budget, priorities, cache and
  a breaker). The `:priority` option of `search/2` (`:admin`, the default, or
  `:player`) says whose request it is (`:gate` names another gate, for tests). The images host is a different server and is not
  counted by the gate.

  Besides the errors of the request, `{:error, :busy}` (no permit in time) and
  `{:error, :blocked}` (the breaker is open) can be returned.
  """
  alias MillenniumQuiz.Cards.Sources.HTTP
  alias MillenniumQuiz.Cards.Sources.YGOPRODeck.Gate

  @base_url "https://db.ygoprodeck.com/api/v7"
  @images_url "https://images.ygoprodeck.com/images"

  # `password` is YGOPRODeck's id, sometimes the one of an alternate artwork;
  # `passwords` lists every artwork's id, the printed password among them.
  @type result :: %{
          password: integer(),
          passwords: [integer()],
          konami_id: integer() | nil,
          name: String.t(),
          card_type: String.t(),
          frame_type: String.t() | nil,
          tcg_release_date: Date.t() | nil
        }

  @doc """
  Cards whose name contains `query`, first released in the TCG by `before`.
  Answers are cached (by query without case and the date), also empty ones.
  """
  @spec search(String.t(), keyword()) :: {:ok, [result()]} | {:error, term()}
  def search(query, opts \\ []) do
    params =
      [fname: query, misc: "yes", num: 20, offset: 0, sort: "name"] ++
        case opts[:before] do
          nil -> []
          date -> [enddate: Date.to_iso8601(date), dateregion: "tcg"]
        end

    key = {:search, query |> String.trim() |> String.downcase(), opts[:before]}

    gate = Keyword.get(opts, :gate, Gate)

    case Gate.cache_get(key, gate) do
      {:ok, results} ->
        {:ok, results}

      :miss ->
        with {:ok, results} <- get(params, Keyword.get(opts, :priority, :admin), gate) do
          Gate.cache_put(key, results, gate)
          {:ok, results}
        end
    end
  end

  @doc """
  One card by any of its ids. Asked by id, the API only lists that one
  artwork, so the card is loaded again by its exact name to get them all.
  """
  @spec fetch(integer()) :: {:ok, result()} | {:error, term()}
  def fetch(password) do
    with {:ok, [card]} <- get([id: password, misc: "yes"], :admin),
         {:ok, [full]} <- get([name: card.name, misc: "yes"], :admin) do
      {:ok, full}
    else
      {:ok, _} -> {:error, :not_found}
      error -> error
    end
  end

  # Served from our own origin later, so only plain image types are accepted
  # (no SVG, which can carry scripts).
  @image_types ~w(image/jpeg image/png image/webp)

  @doc """
  Downloads the artwork of a card id (the cropped picture, 624x624 JPEG).
  YGOPRODeck asks to download images once and host them yourself. Responses
  that are not a plain image are rejected.
  """
  def artwork(id) do
    url = "#{@images_url}/cards_cropped/#{id}.jpg"

    case Req.get(HTTP.new(@images_url), url: "/cards_cropped/#{id}.jpg", decode_body: false) do
      {:ok, %{status: 200, body: data} = response} when byte_size(data) > 0 ->
        content_type =
          case Req.Response.get_header(response, "content-type") do
            [type | _] -> type |> String.split(";") |> hd() |> String.trim() |> String.downcase()
            [] -> "image/jpeg"
          end

        if content_type in @image_types,
          do: {:ok, %{artwork_id: id, data: data, content_type: content_type, source_url: url}},
          else: {:error, {:unexpected_content_type, content_type}}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # One permit from the gate per request. Req's own retries are off: a retry
  # would be a request the gate did not count.
  defp get(params, priority, gate \\ Gate) do
    with :ok <- Gate.acquire(priority, gate) do
      case Req.get(HTTP.new(@base_url, max_retries: 0),
             url: "/cardinfo.php",
             params: params
           ) do
        {:ok, %{status: 200, body: %{"data" => cards}}} ->
          {:ok, Enum.map(cards, &result/1)}

        # "No card matching your query was found in the database."
        {:ok, %{status: 400}} ->
          {:ok, []}

        # what a blocked address looks like: stop asking for a while
        {:ok, %{status: status}} when status in [403, 429] ->
          Gate.trip(nil, gate)
          {:error, {:http, status}}

        {:ok, %{status: status}} ->
          {:error, {:http, status}}

        {:error, reason} ->
          {:error, reason}
      end
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
      frame_type: card["frameType"],
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
