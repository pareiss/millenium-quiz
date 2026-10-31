defmodule MillenniumQuiz.Quiz.AvatarCardDatesTest do
  @moduledoc "Cards that came out after a format's date can't be its pictures."
  use MillenniumQuiz.DataCase, async: true

  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{Avatars, Quiz, Repo}
  alias MillenniumQuiz.Cards.Card
  alias MillenniumQuiz.Quiz.FormatAvatarCard

  defp card!(release) do
    n = System.unique_integer([:positive])

    Repo.insert!(%Card{
      name: "Dated Card #{n}",
      password: n,
      tcg_release_date: release,
      fetched_at: DateTime.utc_now(:second)
    })
  end

  defp rows(format_id),
    do: Repo.aggregate(from(a in FormatAvatarCard, where: a.format_id == ^format_id), :count)

  test "the day of the format is allowed, the day after is not" do
    f = format_fixture(%{"date" => "2010-04-24"})

    assert {:ok, _} = Quiz.add_avatar_card(f.id, card!(~D[2010-04-23]).id)
    assert {:ok, _} = Quiz.add_avatar_card(f.id, card!(~D[2010-04-24]).id)
    assert {:error, :not_released} = Quiz.add_avatar_card(f.id, card!(~D[2010-04-25]).id)
    assert rows(f.id) == 2
  end

  test "cards of years later and of the far future are refused too" do
    f = format_fixture(%{"date" => "2005-04-01"})

    for date <- [~D[2005-05-01], ~D[2006-04-01], ~D[2026-10-31], ~D[9999-12-31]] do
      assert {:error, :not_released} = Quiz.add_avatar_card(f.id, card!(date).id)
    end

    assert Quiz.avatar_cards(f.id) == []
  end

  test "the date is the format's: one card can be a picture of an old format only after the card is out" do
    old = format_fixture(%{"date" => "2005-04-01"})
    new = format_fixture(%{"date" => "2011-09-01"})
    card = card!(~D[2008-06-01])

    assert {:error, :not_released} = Quiz.add_avatar_card(old.id, card.id)
    assert {:ok, _} = Quiz.add_avatar_card(new.id, card.id)
    assert Quiz.avatar_cards(old.id) == []
    assert [%{id: id}] = Quiz.avatar_cards(new.id)
    assert id == card.id
  end

  test "a refused card changes nothing: no row, and the next card takes the next place" do
    f = format_fixture(%{"date" => "2005-04-01"})
    [a, b] = [card!(~D[2002-03-08]), card!(~D[2003-01-01])]

    {:ok, _} = Quiz.add_avatar_card(f.id, a.id)
    assert {:error, :not_released} = Quiz.add_avatar_card(f.id, card!(~D[2020-01-01]).id)
    {:ok, _} = Quiz.add_avatar_card(f.id, b.id)

    assert Enum.map(Quiz.avatar_cards(f.id), & &1.id) == [a.id, b.id]

    positions =
      Repo.all(
        from a in FormatAvatarCard,
          where: a.format_id == ^f.id,
          order_by: a.position,
          select: a.position
      )

    assert positions == Enum.uniq(positions)
  end

  test "asking again for a card that is refused stays refused, and for one that is in stays in once" do
    f = format_fixture(%{"date" => "2005-04-01"})
    late = card!(~D[2006-01-01])
    ok = card!(~D[2004-01-01])

    for _ <- 1..3, do: assert({:error, :not_released} = Quiz.add_avatar_card(f.id, late.id))
    for _ <- 1..3, do: assert({:ok, _} = Quiz.add_avatar_card(f.id, ok.id))
    assert rows(f.id) == 1
  end

  test "a full list says it is full for a card that is out; for one that is not out the date is named first" do
    f = format_fixture(%{"date" => "2005-04-01"})

    for _ <- 1..Quiz.max_avatar_cards(),
        do: {:ok, _} = Quiz.add_avatar_card(f.id, card!(~D[2003-01-01]).id)

    assert {:error, :limit} = Quiz.add_avatar_card(f.id, card!(~D[2004-01-01]).id)
    assert {:error, :not_released} = Quiz.add_avatar_card(f.id, card!(~D[2030-01-01]).id)
    assert rows(f.id) == Quiz.max_avatar_cards()
  end

  test "a list that is refused card by card never becomes the pool of a game" do
    f = format_fixture(%{"date" => "2005-04-01"})

    for _ <- 1..4,
        do: {:error, :not_released} = Quiz.add_avatar_card(f.id, card!(~D[2015-01-01]).id)

    assert Avatars.pool(Quiz.get_format!(f.id)) == Avatars.for_format(~D[2005-04-01])
  end
end
