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

  describe "sets of the formats" do
    test "Edison, Goat and Tengu have a set; the name's case and spaces do not matter" do
      for name <- ~w(Edison Goat Tengu) do
        set = Avatars.for_format(name)
        refute set == Avatars.default_slugs()
        assert Avatars.for_format(String.upcase(name)) == set
        assert Avatars.for_format("  #{String.downcase(name)} ") == set
      end

      refute Avatars.for_format("Edison") == Avatars.for_format("Goat")
    end

    test "any other format, and a name that is not a string, use the default pool" do
      assert Avatars.for_format("HAT Format") == Avatars.default_slugs()
      assert Avatars.for_format("") == Avatars.default_slugs()
      assert Avatars.for_format(nil) == Avatars.default_slugs()
    end

    test "a set has monsters of the pool only, without repeats, for the most players of a game" do
      for name <- ~w(Edison Goat Tengu) do
        set = Avatars.for_format(name)
        assert length(set) >= 4, "#{name} has too few monsters"
        assert set == Enum.uniq(set)
        assert Enum.all?(set, &Avatars.path/1), "#{name} has a slug that is not in the pool"
      end
    end

    test "assign picks from the set it is given" do
      set = Avatars.for_format("Goat")

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
end
