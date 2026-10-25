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
end
