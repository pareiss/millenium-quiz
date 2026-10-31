defmodule MillenniumQuiz.GamesAvatarsTest do
  # Not async: the game servers are other processes that share the connection.
  use MillenniumQuiz.DataCase

  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{Avatars, Game, Games, Quiz}
  alias MillenniumQuiz.Cards.Card
  alias MillenniumQuiz.Games.GameRecord

  @names ["Ann", "Bob", "Cy", "Di"]

  defp card!(n \\ System.unique_integer([:positive])) do
    Repo.insert!(%Card{
      name: "Pic Card #{n}",
      password: n,
      tcg_release_date: ~D[2002-03-08],
      fetched_at: DateTime.utc_now(:second)
    })
  end

  # A playable format whose admin list has `count` cards.
  defp format_with_cards(count) do
    format = playable_format_fixture(1)
    cards = for _ <- 1..count//1, do: card!()
    for card <- cards, do: {:ok, _} = Quiz.add_avatar_card(format.id, card.id)
    {format, cards}
  end

  defp slugs(cards), do: Enum.map(cards, &Avatars.card_slug(&1.id))

  defp avatars_of(id) do
    {:ok, %{game: game}} = Games.fetch_game(id)
    Enum.map(game.players, & &1.avatar)
  end

  defp stored_avatars(id) do
    Repo.get!(GameRecord, id).state
    |> Game.from_map()
    |> Map.fetch!(:players)
    |> Enum.map(& &1.avatar)
  end

  describe "a game with pictures of cards" do
    test "keeps them through play, pause and resume" do
      {format, cards} = format_with_cards(5)
      {:ok, id} = Games.create_game(format.id, @names)
      before = avatars_of(id)

      assert length(Enum.uniq(before)) == 4
      assert Enum.all?(before, &(&1 in slugs(cards)))

      {:ok, _} = Games.choose(id, 0)
      assert avatars_of(id) == before
      {:ok, _} = Games.pause(id)
      assert stored_avatars(id) == before
      {:ok, _} = Games.resume(id)
      assert avatars_of(id) == before
    end

    test "chosen pictures are the ones the game starts with and keeps" do
      {format, cards} = format_with_cards(5)
      [a, b | _] = slugs(cards)

      {:ok, id} = Games.create_game(format.id, @names, avatars: [b, nil, nil, a])
      avatars = avatars_of(id)

      assert [^b, middle1, middle2, ^a] = avatars
      assert length(Enum.uniq([b, a, middle1, middle2])) == 4
      assert stored_avatars(id) == avatars
    end

    test "a card taken off the format's list afterwards stays in the game" do
      {format, cards} = format_with_cards(4)
      {:ok, id} = Games.create_game(format.id, @names)
      before = stored_avatars(id)

      for card <- cards, do: :ok = Quiz.remove_avatar_card(format.id, card.id)

      assert avatars_of(id) == before
    end

    test "a list of fewer cards than the most players gives the built-in pictures" do
      {format, cards} = format_with_cards(3)
      {:ok, id} = Games.create_game(format.id, @names)
      avatars = avatars_of(id)

      assert Enum.all?(avatars, &(&1 in Avatars.pool(%{date: format.date})))
      refute Enum.any?(avatars, &(&1 in slugs(cards)))
      assert length(Enum.uniq(avatars)) == 4
    end

    test "a list of exactly 4 cards is used, and gives each player a different one" do
      {format, cards} = format_with_cards(4)
      {:ok, id} = Games.create_game(format.id, @names)
      assert Enum.sort(avatars_of(id)) == Enum.sort(slugs(cards))
    end

    test "a forged picture is refused and no game is saved" do
      {format, cards} = format_with_cards(4)
      count = Repo.aggregate(GameRecord, :count)
      [a | _] = slugs(cards)

      for bad <- ["card-999999999", "card-0", "jinzo", "../x", "card-1; drop", 5] do
        assert {:error, :invalid_avatar} =
                 Games.create_game(format.id, @names, avatars: [bad, nil, nil, nil])
      end

      assert {:error, :duplicate_avatars} =
               Games.create_game(format.id, @names, avatars: [a, a, nil, nil])

      assert Repo.aggregate(GameRecord, :count) == count
    end
  end

  describe "a card that left the card pool" do
    test "its player gets a default picture, the others keep theirs, and it is saved" do
      {format, cards} = format_with_cards(4)
      {:ok, id} = Games.create_game(format.id, @names)
      before = stored_avatars(id)
      gone = hd(cards)
      Repo.delete!(gone)

      after_load = avatars_of(id)
      refute Avatars.card_slug(gone.id) in after_load
      assert length(Enum.uniq(after_load)) == 4
      assert Enum.count(after_load, &(&1 in Avatars.default_slugs())) == 1

      kept = Enum.reject(before, &(&1 == Avatars.card_slug(gone.id)))
      assert Enum.all?(kept, &(&1 in after_load))

      # the next saved change keeps the replacement
      {:ok, _} = Games.choose(id, 0)
      assert stored_avatars(id) == after_load
    end

    test "every picture can go at once, each player still gets a different default" do
      {format, cards} = format_with_cards(4)
      {:ok, id} = Games.create_game(format.id, @names)
      for card <- cards, do: Repo.delete!(card)

      avatars = avatars_of(id)
      assert length(Enum.uniq(avatars)) == 4
      assert Enum.all?(avatars, &(&1 in Avatars.default_slugs()))
    end

    test "deleting the format's cards from the pool does not break a new game" do
      {format, cards} = format_with_cards(4)
      for card <- cards, do: Repo.delete!(card)

      # the links went with the cards: the format has no list any more
      assert Quiz.avatar_cards(format.id) == []
      {:ok, id} = Games.create_game(format.id, @names)
      assert Enum.all?(avatars_of(id), &(&1 in Avatars.pool(%{date: format.date})))
    end
  end

  describe "games saved before" do
    test "without pictures they load and can be played" do
      format = playable_format_fixture(1)
      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])

      record = Repo.get!(GameRecord, id)

      state =
        Map.update!(record.state, "players", fn ps -> Enum.map(ps, &Map.delete(&1, "avatar")) end)

      record |> Ecto.Changeset.change(state: state) |> Repo.update!()

      assert avatars_of(id) == [nil, nil]
      assert {:ok, _} = Games.choose(id, 0)
    end

    test "with a slug that no longer exists they load, show no picture and can be played" do
      format = playable_format_fixture(1)
      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])

      record = Repo.get!(GameRecord, id)

      state =
        Map.update!(record.state, "players", fn ps ->
          Enum.map(ps, &Map.put(&1, "avatar", "a-monster-that-was-removed"))
        end)

      record |> Ecto.Changeset.change(state: state) |> Repo.update!()

      assert avatars_of(id) == ["a-monster-that-was-removed", "a-monster-that-was-removed"]
      assert Avatars.path("a-monster-that-was-removed") == nil
      assert {:ok, _} = Games.choose(id, 0)
    end
  end
end
