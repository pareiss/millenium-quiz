defmodule MillenniumQuiz.AvatarsTest do
  use ExUnit.Case, async: true

  alias MillenniumQuiz.Avatars

  test "every monster of the pool has its image file" do
    for %{slug: slug} <- Avatars.all() do
      assert File.exists?(Path.join("priv/static/images/avatars", slug <> ".jpg")),
             "missing image for #{slug}, run mix avatars.fetch"
    end
  end

  test "slugs are unique" do
    slugs = Enum.map(Avatars.all(), & &1.slug)
    assert slugs == Enum.uniq(slugs)
  end

  test "assign gives different monsters, in the order shuffle leaves them" do
    assert Avatars.assign(3, & &1) == Enum.take(Enum.map(Avatars.all(), & &1.slug), 3)
    assert Avatars.assign(4) |> Enum.uniq() |> length() == 4
    assert Avatars.assign(0) == []
  end

  test "path and name only know the pool" do
    assert Avatars.path("jinzo") == "/images/avatars/jinzo.jpg"
    assert Avatars.name("jinzo") == "Jinzo"
    assert Avatars.path("../../etc/passwd") == nil
    assert Avatars.path(nil) == nil
    assert Avatars.name("nope") == nil
  end

  @set_dates [~D[2010-04-24], ~D[2005-04-01], ~D[2011-09-01]]

  describe "sets of the formats" do
    test "Edison, Goat and Tengu have a set, found by the format's date" do
      for date <- @set_dates do
        refute Avatars.for_format(date) == Avatars.default_slugs()
      end

      assert Enum.uniq(Enum.map(@set_dates, &Avatars.for_format/1)) |> length() == 3
    end

    test "any other date, and anything that is not a date, use the default pool" do
      assert Avatars.for_format(~D[2007-01-01]) == Avatars.default_slugs()
      assert Avatars.for_format(nil) == Avatars.default_slugs()
      assert Avatars.for_format("Goat") == Avatars.default_slugs()
    end

    test "a set has monsters of the pool only, without repeats, for the most players of a game" do
      for date <- @set_dates do
        set = Avatars.for_format(date)
        assert length(set) >= 4, "#{date} has too few monsters"
        assert set == Enum.uniq(set)
        assert Enum.all?(set, &Avatars.path/1), "#{date} has a slug that is not in the pool"
      end
    end

    test "assign picks from the set it is given" do
      set = Avatars.for_format(~D[2005-04-01])

      for _ <- 1..20 do
        assert Avatars.assign(4, &Enum.shuffle/1, set) -- set == []
      end

      assert Avatars.assign(2, & &1, set) == Enum.take(set, 2)
    end

    test "the default pool keeps its eight monsters, so saved games still show theirs" do
      assert length(Avatars.default_slugs()) == 8
      assert "jinzo" in Avatars.default_slugs()
    end
  end

  describe "card slugs" do
    test "card_slug and card_id round trip" do
      assert Avatars.card_slug(42) == "card-42"
      assert Avatars.card_id("card-42") == 42

      assert Avatars.card_id(Avatars.card_slug(9_223_372_036_854_775_807)) ==
               9_223_372_036_854_775_807
    end

    test "only canonical slugs of the bigint range are card slugs" do
      for bad <- [
            "card-0",
            "card-007",
            "card-01",
            "card--1",
            "card-",
            "card",
            "Card-1",
            "card-1 ",
            "card-1\n",
            " card-1",
            "card-1; drop table cards",
            "card-1.5",
            "card-9223372036854775808",
            "card-99999999999999999999999",
            "jinzo",
            nil,
            1,
            :"card-1"
          ] do
        assert Avatars.card_id(bad) == nil, inspect(bad)
        if bad not in ["jinzo"], do: assert(Avatars.path(bad) == nil, inspect(bad))
      end
    end

    test "path serves the artwork, name has no database to ask" do
      assert Avatars.path("card-7") == "/cards/7/artwork?w=200"
      assert Avatars.name("card-7") == nil
      assert_raise FunctionClauseError, fn -> Avatars.card_slug(0) end
      assert_raise FunctionClauseError, fn -> Avatars.card_slug(-1) end
    end
  end

  describe "pool/1" do
    test "card links make card slugs in order, else the date set" do
      links = for id <- [9, 2, 7, 4], do: %{card_id: id}

      assert Avatars.pool(%{date: ~D[2010-04-24], avatar_cards: links}) ==
               ["card-9", "card-2", "card-7", "card-4"]

      # fewer cards than the most players of a game: not used
      assert Avatars.pool(%{date: ~D[2010-04-24], avatar_cards: Enum.take(links, 3)}) ==
               Avatars.for_format(~D[2010-04-24])

      for avatar_cards <- [[], %Ecto.Association.NotLoaded{}, nil] do
        assert Avatars.pool(%{date: ~D[2010-04-24], avatar_cards: avatar_cards}) ==
                 Avatars.for_format(~D[2010-04-24])
      end

      assert Avatars.pool(%{date: ~D[2010-04-24]}) == Avatars.for_format(~D[2010-04-24])
    end
  end

  describe "assign with chosen slugs" do
    test "chosen players keep theirs, the others get different ones without them" do
      pool = ~w(a b c d)
      assert Avatars.assign(3, & &1, pool, ["c", nil, nil]) == ["c", "a", "b"]
      assert Avatars.assign(3, & &1, pool, [nil, "a"]) == ["b", "a", "c"]
      assert Avatars.assign(2, & &1, pool, []) == ["a", "b"]
      assert Avatars.assign(2, & &1, pool, ["x", nil]) == ["x", "a"]
    end

    test "when the chosen use up the pool the others repeat from it" do
      assert Avatars.assign(2, & &1, ["a"], ["a", nil]) == ["a", "a"]
      assert Avatars.assign(2, & &1, [], [nil, nil]) == [nil, nil]
    end
  end
end
