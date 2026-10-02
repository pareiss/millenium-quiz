defmodule MillenniumQuiz.CardSourcesStub do
  @moduledoc """
  Stands in for YGOPRODeck, YAML Yugi and Yugipedia in tests. Knows two
  cards: Monster Reborn (real errata page, listed by YGOPRODeck under an
  alternate artwork id) and "Plain Card" (no errata page).
  """

  @reborn %{konami_id: 4842, ids: [83_764_719, 83_764_718], password: 83_764_718, page_id: 24}
  @plain %{konami_id: 9001, ids: [11_111_111], password: 11_111_111, page_id: 9001}

  @release_dates %{
    "Legend of Blue Eyes White Dragon" => "1/2002/3/8",
    "Collectible Tins 2003" => "1/2003/9",
    "Starter Deck: Yugi Evolution" => "1/2004/3/1",
    "Hobby League 7 participation card A" => "1/2008/7",
    "Legendary Collection" => "1/2010/10/5",
    "Legendary Collection 3: Yugi's World Mega Pack" => "1/2012/10/2",
    "Battles of Legend: Relentless Revenge" => "1/2018/6/29",
    "2019 Gold Sarcophagus Tin" => "1/2019/8/30"
  }

  def reborn, do: @reborn
  def plain, do: @plain

  @doc "Routes every card source request of the calling test (and `shared` processes)."
  def stub! do
    Req.Test.stub(MillenniumQuiz.Cards, &handle/1)
  end

  def handle(%Plug.Conn{host: "db.ygoprodeck.com"} = conn) do
    params = Plug.Conn.fetch_query_params(conn).query_params

    cards =
      cond do
        params["fname"] ->
          before = params["enddate"] && Date.from_iso8601!(params["enddate"])
          query = String.downcase(params["fname"])

          for card <- [ygoprodeck(:reborn, :all), ygoprodeck(:plain, :all)],
              String.contains?(String.downcase(card["name"]), query),
              is_nil(before) or Date.compare(Date.from_iso8601!(tcg_date(card)), before) != :gt,
              do: card

        params["id"] in Enum.map(@reborn.ids, &to_string/1) ->
          [ygoprodeck(:reborn, String.to_integer(params["id"]))]

        params["id"] == "11111111" ->
          [ygoprodeck(:plain, :all)]

        params["name"] == "Monster Reborn" ->
          [ygoprodeck(:reborn, :all)]

        params["name"] == "Plain Card" ->
          [ygoprodeck(:plain, :all)]

        true ->
          []
      end

    if cards == [],
      do: json(conn, 400, %{error: "No card matching your query was found in the database."}),
      else: json(conn, 200, %{data: cards})
  end

  def handle(%Plug.Conn{host: "cdn.jsdelivr.net", request_path: path} = conn) do
    cond do
      String.ends_with?(path, "/83764718.json") ->
        json(
          conn,
          200,
          yaml_yugi(
            @reborn,
            "Monster Reborn",
            "Wiedergeburt",
            "Target 1 monster in either GY; Special Summon it."
          )
        )

      String.ends_with?(path, "/11111111.json") ->
        json(conn, 200, yaml_yugi(@plain, "Plain Card", "Einfache Karte", "Draw 1 card."))

      true ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(404, "Not found")
    end
  end

  def handle(%Plug.Conn{host: "yugipedia.com"} = conn) do
    params = Plug.Conn.fetch_query_params(conn).query_params

    case params do
      %{"action" => "query", "pageids" => "24"} ->
        json(conn, 200, %{query: %{pages: [%{pageid: 24, title: "Monster Reborn"}]}})

      %{"action" => "query", "pageids" => "9001"} ->
        json(conn, 200, %{query: %{pages: [%{pageid: 9001, title: "Plain Card"}]}})

      %{"action" => "parse", "page" => "Card Errata:Monster Reborn"} ->
        wikitext = File.read!("test/support/fixtures/errata/monster_reborn.wikitext")
        json(conn, 200, %{parse: %{title: "Card Errata:Monster Reborn", wikitext: wikitext}})

      %{"action" => "parse"} ->
        json(conn, 200, %{
          error: %{code: "missingtitle", info: "The page you specified doesn't exist."}
        })

      %{"action" => "ask", "query" => query} ->
        results =
          for {set, date} <- @release_dates, String.contains?(query, set), into: %{} do
            {set, %{printouts: %{"North American English release date" => [%{raw: date}]}}}
          end

        json(conn, 200, %{query: %{results: if(results == %{}, do: [], else: results)}})
    end
  end

  defp ygoprodeck(:reborn, artwork) do
    images = if artwork == :all, do: @reborn.ids, else: [artwork]

    %{
      "id" => hd(images),
      "name" => "Monster Reborn",
      "type" => "Spell Card",
      "humanReadableCardType" => "Normal Spell",
      "card_images" => Enum.map(images, &%{"id" => &1}),
      "misc_info" => [%{"konami_id" => @reborn.konami_id, "tcg_date" => "2002-03-08"}]
    }
  end

  defp ygoprodeck(:plain, _artwork) do
    %{
      "id" => 11_111_111,
      "name" => "Plain Card",
      "type" => "Spell Card",
      "humanReadableCardType" => "Normal Spell",
      "card_images" => [%{"id" => 11_111_111}],
      "misc_info" => [%{"konami_id" => @plain.konami_id, "tcg_date" => "2015-05-05"}]
    }
  end

  defp tcg_date(card), do: hd(card["misc_info"])["tcg_date"]

  defp yaml_yugi(card, name, german_name, text) do
    %{
      password: card.password,
      konami_id: card.konami_id,
      yugipedia_page_id: card.page_id,
      name: %{en: name, de: german_name, ja: "<ruby>死<rt>し</rt></ruby>者"},
      text: %{en: text, de: "Text auf Deutsch."}
    }
  end

  defp json(conn, status, body) do
    conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)
  end
end
