defmodule MillenniumQuiz.Quiz.AvatarCardsTest do
  use MillenniumQuiz.DataCase, async: true

  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{Avatars, Game, Games, Quiz}
  alias MillenniumQuiz.Cards.Card
  alias MillenniumQuiz.Quiz.FormatAvatarCard

  defp card!(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    Repo.insert!(
      struct!(
        Card,
        Map.merge(
          %{
            name: "Avatar Card #{n}",
            password: n,
            tcg_release_date: ~D[2002-03-08],
            fetched_at: DateTime.utc_now(:second)
          },
          attrs
        )
      )
    )
  end

  defp format!(date \\ "2005-04-01"), do: format_fixture(%{"date" => date})

  test "cards are added at the end, once, and listed without artwork" do
    f = format!()
    [a, b, c] = [card!(), card!(), card!()]

    for card <- [b, a, c], do: assert({:ok, _} = Quiz.add_avatar_card(f.id, card.id))
    assert {:ok, again} = Quiz.add_avatar_card(f.id, a.id)
    assert again.card_id == a.id

    assert Enum.map(Quiz.avatar_cards(f.id), & &1.id) == [b.id, a.id, c.id]
    assert [%Card{name: name, password: password} | _] = Quiz.avatar_cards(f.id)
    assert name == b.name and password == b.password
    # only id, name and password are selected
    assert hd(Quiz.avatar_cards(f.id)).tcg_release_date == nil
    assert Repo.aggregate(FormatAvatarCard, :count) == 3
  end

  test "remove keeps the order of the others and is harmless twice" do
    f = format!()
    [a, b, c] = [card!(), card!(), card!()]
    for card <- [a, b, c], do: Quiz.add_avatar_card(f.id, card.id)

    assert :ok = Quiz.remove_avatar_card(f.id, b.id)
    assert :ok = Quiz.remove_avatar_card(f.id, b.id)
    assert Enum.map(Quiz.avatar_cards(f.id), & &1.id) == [a.id, c.id]

    # a new card still goes to the end
    {:ok, _} = Quiz.add_avatar_card(f.id, b.id)
    assert Enum.map(Quiz.avatar_cards(f.id), & &1.id) == [a.id, c.id, b.id]
  end

  test "a format holds at most max_avatar_cards, adding a present one still works" do
    f = format!()
    max = Quiz.max_avatar_cards()
    assert max == 40
    cards = for _ <- 1..max, do: card!()
    for card <- cards, do: assert({:ok, _} = Quiz.add_avatar_card(f.id, card.id))

    assert {:error, :limit} = Quiz.add_avatar_card(f.id, card!().id)
    assert {:ok, _} = Quiz.add_avatar_card(f.id, hd(cards).id)
    assert length(Quiz.avatar_cards(f.id)) == max
  end

  test "only cards released by the format's date, no release date counts as released" do
    f = format!("2005-04-01")
    late = card!(%{tcg_release_date: ~D[2005-04-02]})
    same_day = card!(%{tcg_release_date: ~D[2005-04-01]})
    unknown = card!(%{tcg_release_date: nil})

    assert {:error, :not_released} = Quiz.add_avatar_card(f.id, late.id)
    assert {:ok, _} = Quiz.add_avatar_card(f.id, same_day.id)
    assert {:ok, _} = Quiz.add_avatar_card(f.id, unknown.id)
    assert Enum.map(Quiz.avatar_cards(f.id), & &1.id) == [same_day.id, unknown.id]
  end

  test "unknown formats and cards" do
    f = format!()
    assert {:error, :not_found} = Quiz.add_avatar_card(f.id, 0)
    assert {:error, :not_found} = Quiz.add_avatar_card(0, card!().id)
    assert Quiz.avatar_cards(0) == []
  end

  test "lists are per format, and go with the format or the card" do
    [f1, f2] = [format!(), format!()]
    [a, b] = [card!(), card!()]
    {:ok, _} = Quiz.add_avatar_card(f1.id, a.id)
    {:ok, _} = Quiz.add_avatar_card(f2.id, a.id)
    {:ok, _} = Quiz.add_avatar_card(f2.id, b.id)

    Repo.delete!(Repo.get!(MillenniumQuiz.Quiz.Format, f1.id))
    assert Enum.map(Quiz.avatar_cards(f2.id), & &1.id) == [a.id, b.id]

    Repo.delete!(a)
    assert Enum.map(Quiz.avatar_cards(f2.id), & &1.id) == [b.id]
  end

  describe "the pool of a format" do
    test "the admin list beats the date set, an empty list falls back" do
      f = format!("2010-04-24")
      assert Avatars.pool(Quiz.get_format!(f.id)) == Avatars.for_format(~D[2010-04-24])

      [a, b, c, d] = [card!(), card!(), card!(), card!()]
      for card <- [b, a, c], do: {:ok, _} = Quiz.add_avatar_card(f.id, card.id)

      # three cards are fewer than the most players of a game: not used yet
      assert Avatars.pool(Quiz.get_format!(f.id)) == Avatars.for_format(~D[2010-04-24])

      {:ok, _} = Quiz.add_avatar_card(f.id, d.id)

      assert Avatars.pool(Quiz.get_format!(f.id)) ==
               Enum.map([b, a, c, d], &Avatars.card_slug(&1.id))

      for card <- [a, b, c, d], do: :ok = Quiz.remove_avatar_card(f.id, card.id)
      assert Avatars.pool(Quiz.get_format!(f.id)) == Avatars.for_format(~D[2010-04-24])
    end

    test "a format without its links loaded uses the date set" do
      f = format!("2010-04-24")
      {:ok, _} = Quiz.add_avatar_card(f.id, card!().id)
      bare = Repo.get!(MillenniumQuiz.Quiz.Format, f.id)
      assert Avatars.pool(bare) == Avatars.for_format(~D[2010-04-24])
    end
  end

  describe "creating a game" do
    setup do
      f = playable_format_fixture(1)
      cards = for _ <- 1..4, do: card!()
      for card <- cards, do: {:ok, _} = Quiz.add_avatar_card(f.id, card.id)
      %{format: f, slugs: Enum.map(cards, &Avatars.card_slug(&1.id))}
    end

    test "players get different cards of the list, and keep them in the snapshot", ctx do
      {:ok, id} = Games.create_game(ctx.format.id, ["Ann", "Bob", "Cy", "Di"])
      game = Repo.get!(MillenniumQuiz.Games.GameRecord, id).state |> Game.from_map()
      avatars = Enum.map(game.players, & &1.avatar)
      assert Enum.sort(avatars) == Enum.sort(ctx.slugs)
      assert length(Enum.uniq(avatars)) == 4
      assert Enum.all?(avatars, &Avatars.path/1)
    end

    test "chosen avatars are passed through", ctx do
      [a, _b, c, _d] = ctx.slugs
      {:ok, id} = Games.create_game(ctx.format.id, ["Ann", "Bob", "Cy"], avatars: [c, nil, a])
      game = Repo.get!(MillenniumQuiz.Games.GameRecord, id).state |> Game.from_map()
      assert [^c, middle, ^a] = Enum.map(game.players, & &1.avatar)
      assert middle in ctx.slugs
    end

    test "invalid and duplicate choices are refused", ctx do
      [a | _] = ctx.slugs
      names = ["Ann", "Bob"]

      assert {:error, :invalid_avatar} =
               Games.create_game(ctx.format.id, names, avatars: ["jinzo", nil])

      assert {:error, :duplicate_avatars} =
               Games.create_game(ctx.format.id, names, avatars: [a, a])
    end
  end

  describe "a card that left the card pool" do
    setup do
      f = playable_format_fixture(1)
      cards = for _ <- 1..4, do: card!()
      for card <- cards, do: {:ok, _} = Quiz.add_avatar_card(f.id, card.id)
      {:ok, id} = Games.create_game(f.id, ["Ann", "Bob", "Cy", "Di"])
      %{id: id, cards: cards}
    end

    test "its players get a different picture of the default pool, the others keep theirs",
         ctx do
      [gone | _] = ctx.cards
      Repo.delete!(gone)

      game =
        Repo.get!(MillenniumQuiz.Games.GameRecord, ctx.id).state
        |> Game.from_map()
        |> Games.heal_avatars()

      avatars = Enum.map(game.players, & &1.avatar)

      refute Avatars.card_slug(gone.id) in avatars
      assert length(Enum.uniq(avatars)) == 4
      kept = Enum.map(tl(ctx.cards), &Avatars.card_slug(&1.id))
      assert Enum.count(avatars, &(&1 in kept)) == 3
      assert Enum.count(avatars, &(&1 in Avatars.default_slugs())) == 1
      assert Enum.all?(avatars, &Avatars.path/1)
    end

    test "the replacement is the same every time the game is loaded", ctx do
      Repo.delete!(hd(ctx.cards))
      game = Repo.get!(MillenniumQuiz.Games.GameRecord, ctx.id).state |> Game.from_map()
      assert Games.heal_avatars(game) == Games.heal_avatars(game)
    end

    test "nothing changes while every card is there", ctx do
      game = Repo.get!(MillenniumQuiz.Games.GameRecord, ctx.id).state |> Game.from_map()
      assert Games.heal_avatars(game) == game
    end
  end
end
