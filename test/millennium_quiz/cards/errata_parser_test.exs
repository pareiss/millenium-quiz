defmodule MillenniumQuiz.Cards.ErrataParserTest do
  use ExUnit.Case, async: true

  alias MillenniumQuiz.Cards.ErrataParser

  @monster_reborn File.read!("test/support/fixtures/errata/monster_reborn.wikitext")

  test "every English version is the full text, with the product it was printed in" do
    versions = ErrataParser.parse(@monster_reborn)["en"]
    assert length(versions) == 8

    # version 0 only changed "Magic" to "Spell" and has no lore: same text as 1
    assert %{version: 0, set: "Legend of Blue Eyes White Dragon", text: original} =
             Enum.at(versions, 0)

    assert original ==
             "Select 1 Monster Card from either your opponent's or your own Graveyard and " <>
               "place it on the field under your control in Attack or Defense Position " <>
               "(face-up). This is considered a Special Summon."

    assert Enum.at(versions, 1).text == original
    assert Enum.at(versions, 1).set == "Collectible Tins 2003"

    # <ins>/<del> inside each other are annotation only, the words stay
    assert %{set: "Starter Deck: Yugi Evolution", text: sye} = Enum.at(versions, 2)

    assert sye ==
             "Select 1 monster from either you or your opponent's Graveyard. " <>
               "Special Summon the selected monster on your side of the field."

    assert %{version: 7, set: "2019 Gold Sarcophagus Tin"} = List.last(versions)
    assert List.last(versions).text == "Target 1 monster in either GY; Special Summon it."
  end

  test "other languages are parsed too, Ruby markup keeps the base text" do
    ja = ErrataParser.parse(@monster_reborn)["ja"]
    assert %{set: "Vol.2", text: "相手か自分の墓場にあるモンスターを、自分のコントロールでフィールド上に出せる。"} = hd(ja)
  end

  test "clean/1 removes markup" do
    assert ErrataParser.clean("<ins>Add</ins> 1 '''monster''' [[Card|cards]]<br />● {{Ruby|魔|ま}}") ==
             "Add 1 monster cards\n● 魔"

    assert ErrataParser.clean("デッキを切り直す。<hr style=\"x\"/><p>{{Ruby|攻|こう}} 1100</p>") ==
             "デッキを切り直す。"
  end

  test "pages without lore give no versions" do
    assert ErrataParser.parse("{{Errata table|lang=fr\n| name0 = A\n| cap0 = [[X]]\n}}") == %{}
  end
end
