defmodule MillenniumQuiz.CardsTest do
  use MillenniumQuiz.DataCase, async: true

  alias MillenniumQuiz.{Cards, CardSourcesStub}
  alias MillenniumQuiz.Cards.{Card, CardText}

  setup do
    CardSourcesStub.stub!()
    :ok
  end

  describe "search/2" do
    test "needs 3 characters and only lists cards released by the format date" do
      assert {:ok, []} = Cards.search("re", %{date: ~D[2020-01-01]})

      assert {:ok, [%{name: "Monster Reborn", konami_id: 4842, in_pool: false}]} =
               Cards.search("reborn", %{date: ~D[2004-01-01]})

      assert {:ok, []} = Cards.search("plain", %{date: ~D[2004-01-01]})
      assert {:ok, [%{name: "Plain Card"}]} = Cards.search("plain", %{date: ~D[2016-01-01]})
    end

    test "marks cards that are already in the pool" do
      {:ok, _} = Cards.import(83_764_719)
      assert {:ok, [%{in_pool: true}]} = Cards.search("reborn", %{date: ~D[2020-01-01]})
    end
  end

  describe "import/1" do
    test "stores names, texts and every errata version with its release date" do
      assert {:ok, card} = Cards.import(83_764_719)

      # stored under the printed password, not YGOPRODeck's artwork id
      assert %Card{password: 83_764_718, konami_id: 4842, name: "Monster Reborn"} = card
      assert card.card_type == "Normal Spell"
      assert card.tcg_release_date == ~D[2002-03-08]
      assert card.names["de"] == "Wiedergeburt"
      assert card.names["ja"] == "死者"

      en = for %{language: "en"} = t <- card.card_texts, do: {t.version, t.released_on}
      assert length(en) == 8
      assert {2, ~D[2004-03-01]} in en
      assert Enum.any?(card.card_texts, &(&1.language == "ja"))

      # the pool answers the second time, also for another artwork id
      assert {:ok, %Card{id: id}} = Cards.import(83_764_718)
      assert id == card.id
      assert Repo.aggregate(Card, :count) == 1
    end

    test "a card without errata gets its current text, dated with its release" do
      assert {:ok, card} = Cards.import(11_111_111)

      assert [%CardText{language: "en", version: 0, text: "Draw 1 card.", set: nil}] =
               card.card_texts

      assert hd(card.card_texts).released_on == ~D[2015-05-05]
    end

    test "unknown cards are an error" do
      assert {:error, :not_found} = Cards.import(12345)
    end
  end

  describe "text_on/3" do
    setup do
      {:ok, card} = Cards.import(83_764_719)
      %{card: card}
    end

    test "is the newest wording printed by the date", %{card: card} do
      assert %{set: "Legend of Blue Eyes White Dragon", text: "Select 1 Monster Card" <> _} =
               Cards.text_on(card, ~D[2003-01-01])

      assert %{set: "Starter Deck: Yugi Evolution", released_on: ~D[2004-03-01]} =
               Cards.text_on(card, ~D[2004-06-01])

      assert %{set: "Legendary Collection 3: Yugi's World Mega Pack"} =
               Cards.text_on(card, ~D[2013-01-01])

      assert %{text: "Target 1 monster in either GY; Special Summon it."} =
               Cards.text_on(card, ~D[2020-01-01])

      assert Cards.text_on(card, nil) == Cards.text_on(card, ~D[2020-01-01])
    end

    test "before the first print it is the oldest wording", %{card: card} do
      assert %{set: "Legend of Blue Eyes White Dragon"} = Cards.text_on(card, ~D[2000-01-01])
    end

    test "reprints of an older wording are not errata" do
      card = %Card{
        texts: %{"en" => "Draw 2 cards."},
        card_texts: [
          %CardText{
            language: "en",
            version: 0,
            text: "Draw 2 cards from your Deck.",
            set: "LOB",
            released_on: ~D[2002-03-08]
          },
          %CardText{
            language: "en",
            version: 1,
            text: "Draw 2 cards.",
            set: "DPKB",
            released_on: ~D[2010-04-20]
          },
          %CardText{
            language: "en",
            version: 2,
            text: "Draw 2 cards from your Deck.",
            set: "LC01",
            released_on: ~D[2010-10-05]
          }
        ]
      }

      assert %{text: "Draw 2 cards.", set: "DPKB"} = Cards.text_on(card, ~D[2011-01-01])
    end

    test "languages without versions use the current text", %{card: card} do
      assert %{text: "Text auf Deutsch.", set: nil} = Cards.text_on(card, ~D[2004-01-01], "de")
    end
  end
end
