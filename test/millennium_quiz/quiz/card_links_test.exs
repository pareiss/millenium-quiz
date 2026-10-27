defmodule MillenniumQuiz.Quiz.CardLinksTest do
  use ExUnit.Case, async: true

  alias MillenniumQuiz.Quiz.CardLinks

  @cards [
    %{name: "Blue-Eyes White Dragon"},
    %{name: "Dark Magician"},
    %{name: "Gaia the Fierce Knight"},
    %{name: "A Hero Lives"},
    %{name: "Mr. Volcano's Fury"}
  ]

  describe "parse/2" do
    test "links cards by case-insensitive exact name with their index" do
      assert [
               {:text, "Who beats "},
               {:card, "blue-eyes white dragon", 0},
               {:text, " with "},
               {:card, "Dark Magician", 1},
               {:text, "?"}
             ] =
               CardLinks.parse("Who beats [blue-eyes white dragon] with [Dark Magician]?", @cards)
    end

    test "adjacent links and links at the edges" do
      assert [{:card, "Dark Magician", 1}, {:card, "Dark Magician", 1}] =
               CardLinks.parse("[Dark Magician][Dark Magician]", @cards)

      assert [{:card, "Dark Magician", 1}, {:text, " "}, {:card, "A Hero Lives", 3}] =
               CardLinks.parse("[Dark Magician] [A Hero Lives]", @cards)
    end

    test "apostrophes, dots and spaces inside the brackets" do
      assert [{:card, "Mr. Volcano's Fury", 4}] =
               CardLinks.parse("[ Mr. Volcano's Fury ]", @cards)
    end

    test "duplicate card names resolve to the first card" do
      assert [{:card, "Dark Magician", 0}] =
               CardLinks.parse("[Dark Magician]", [
                 %{name: "Dark Magician"},
                 %{name: "dark magician"}
               ])
    end

    test "unmatched brackets stay text, brackets kept" do
      assert [{:text, "He said [sic] and [Unknown Card]."}] =
               CardLinks.parse("He said [sic] and [Unknown Card].", @cards)
    end

    test "unclosed, empty and nested brackets" do
      assert [{:text, "[Dark Magician"}] = CardLinks.parse("[Dark Magician", @cards)
      assert [{:text, "Dark Magician]"}] = CardLinks.parse("Dark Magician]", @cards)
      assert [{:text, "a [] b [ ] c"}] = CardLinks.parse("a [] b [ ] c", @cards)

      assert [{:text, "[a "}, {:card, "Dark Magician", 1}, {:text, "]"}] =
               CardLinks.parse("[a [Dark Magician]]", @cards)
    end

    test "no cards, empty and nil text" do
      assert [{:text, "[Dark Magician]"}] = CardLinks.parse("[Dark Magician]", [])
      assert [] = CardLinks.parse("", @cards)
      assert [] = CardLinks.parse(nil, @cards)
    end

    test "unicode text" do
      assert [{:text, "Größe – "}, {:card, "Dark Magician", 1}, {:text, " ✓"}] =
               CardLinks.parse("Größe – [Dark Magician] ✓", @cards)

      assert [{:card, "ÖLFASS", 0}] = CardLinks.parse("[ÖLFASS]", [%{name: "Ölfass"}])
    end
  end

  describe "names/1" do
    test "lists the bracketed names in order, without duplicates" do
      assert ["Dark Magician", "Blue-Eyes White Dragon", "Nope"] =
               CardLinks.names("[Dark Magician] [Blue-Eyes White Dragon][dark magician] [Nope]")
    end

    test "ignores empty, unclosed and nested" do
      assert [] = CardLinks.names("[] [ ] [unclosed")
      assert ["Dark Magician"] = CardLinks.names("[a [Dark Magician]] [x")
      assert [] = CardLinks.names(nil)
    end
  end

  describe "unlink/2" do
    test "removes the brackets of every occurrence, case-insensitive" do
      assert "Dark Magician beats dark magician, not [Gaia the Fierce Knight] or [sic]." =
               CardLinks.unlink(
                 "[Dark Magician] beats [dark magician], not [Gaia the Fierce Knight] or [sic].",
                 "DARK MAGICIAN"
               )
    end

    test "leaves everything else alone" do
      assert "[a] [Dark Magician" = CardLinks.unlink("[a] [Dark Magician", "Dark Magician")
      assert "" = CardLinks.unlink(nil, "x")
    end
  end

  describe "player markers" do
    test "{P1} and {P2} in any case become player segments" do
      assert [
               {:player, 1},
               {:text, " attacks "},
               {:card, "Dark Magician", 1},
               {:text, " of "},
               {:player, 2},
               {:player, 2}
             ] = CardLinks.parse("{P1} attacks [Dark Magician] of {p2}{P2}", @cards)
    end

    test "other braces stay text, and a marker in brackets is no marker" do
      assert [{:text, "{P3} {P} {} {P1 {"}, {:player, 1}] =
               CardLinks.parse("{P3} {P} {} {P1 {{P1}", @cards)

      assert [{:text, "[{P1}]"}] = CardLinks.parse("[{P1}]", @cards)
    end

    test "plain/2 can keep the markers for a caller that draws them" do
      assert "{P1} beats Dark Magician" =
               CardLinks.plain("{P1} beats [Dark Magician]", keep_players: true)
    end

    test "plain/1 reads the text like parse/2: a marker in brackets is no marker" do
      assert "{P1} and P2" = CardLinks.plain("[{P1}] and {P2}")
      assert "[] [ ] {P3}" = CardLinks.plain("[] [ ] {P3}")
    end

    test "plain/1 writes P1 and P2" do
      assert "P1 beats P2 with Dark Magician" =
               CardLinks.plain("{P1} beats {p2} with [Dark Magician]")
    end
  end

  describe "plain/1" do
    test "replaces every bracket pair with its name" do
      assert "Dark Magician and Mr. Volcano's Fury and Anything" =
               CardLinks.plain("[Dark Magician] and [ Mr. Volcano's Fury ] and [Anything]")
    end

    test "keeps empty, unclosed and stray brackets" do
      assert "[] [ ] [open x y" = CardLinks.plain("[] [ ] [open x y")
      assert "[a Dark Magician" = CardLinks.plain("[a [Dark Magician]")
      assert "" = CardLinks.plain(nil)
    end
  end
end
