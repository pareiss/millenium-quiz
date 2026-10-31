defmodule MillenniumQuiz.Quiz.AvatarCropsTest do
  use MillenniumQuiz.DataCase, async: true

  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{Avatars, Quiz}
  alias MillenniumQuiz.Cards.Card
  alias MillenniumQuiz.Quiz.CardAvatarCrop

  defp card! do
    n = System.unique_integer([:positive])

    Repo.insert!(%Card{
      name: "Crop Card #{n}",
      password: n,
      tcg_release_date: ~D[2002-03-08],
      fetched_at: DateTime.utc_now(:second)
    })
  end

  @crop %{x: 20, y: 70, zoom: 200}

  describe "Avatars.crop_box/1" do
    test "the default crop is centred and 150% large" do
      assert Avatars.default_crop() == %{x: 50, y: 50, zoom: 150}

      assert Avatars.crop_box(Avatars.default_crop()) ==
               %{size: 150.0, left: -25.0, top: -25.0}
    end

    test "the focus point lands in the middle when the image can move that far" do
      # 50 - 60 * 200 / 100 = -70, within 100 - 200 = -100 .. 0
      assert %{size: 200.0, left: -70.0, top: -70.0} =
               Avatars.crop_box(%{x: 60, y: 60, zoom: 200})
    end

    test "edges are clamped so the image covers the container" do
      assert Avatars.crop_box(%{x: 0, y: 0, zoom: 150}) == %{size: 150.0, left: 0.0, top: 0.0}

      assert Avatars.crop_box(%{x: 100, y: 100, zoom: 150}) == %{
               size: 150.0,
               left: -50.0,
               top: -50.0
             }

      assert Avatars.crop_box(%{x: 5, y: 100, zoom: 300}) == %{
               size: 300.0,
               left: 0.0,
               top: -200.0
             }
    end

    test "zoom 100 never moves" do
      for x <- [0, 50, 100], y <- [0, 50, 100] do
        assert Avatars.crop_box(%{x: x, y: y, zoom: 100}) == %{size: 100.0, left: 0.0, top: 0.0}
      end
    end
  end

  describe "set, read and reset" do
    test "no row means the default" do
      c = card!()
      assert Quiz.avatar_crop(c.id) == Avatars.default_crop()
    end

    test "set stores, replaces and returns the crop" do
      c = card!()
      assert {:ok, @crop} = Quiz.set_avatar_crop(c.id, @crop)
      assert Quiz.avatar_crop(c.id) == @crop

      assert {:ok, %{x: 0, y: 100, zoom: 300}} =
               Quiz.set_avatar_crop(c.id, %{x: 0, y: 100, zoom: 300})

      assert Quiz.avatar_crop(c.id) == %{x: 0, y: 100, zoom: 300}
      assert Repo.aggregate(CardAvatarCrop, :count) == 1
    end

    test "the default crop deletes the row" do
      c = card!()
      {:ok, _} = Quiz.set_avatar_crop(c.id, @crop)

      assert {:ok, %{x: 50, y: 50, zoom: 150}} =
               Quiz.set_avatar_crop(c.id, Avatars.default_crop())

      assert Repo.get(CardAvatarCrop, c.id) == nil

      # and does not create one
      assert {:ok, _} = Quiz.set_avatar_crop(c.id, Avatars.default_crop())
      assert Repo.get(CardAvatarCrop, c.id) == nil
    end

    test "reset deletes the row and is harmless twice" do
      c = card!()
      {:ok, _} = Quiz.set_avatar_crop(c.id, @crop)
      assert :ok = Quiz.reset_avatar_crop(c.id)
      assert :ok = Quiz.reset_avatar_crop(c.id)
      assert Quiz.avatar_crop(c.id) == Avatars.default_crop()
    end

    test "out of range, non-integer and incomplete crops are invalid" do
      c = card!()

      for bad <- [
            %{x: -1, y: 50, zoom: 150},
            %{x: 101, y: 50, zoom: 150},
            %{x: 50, y: -1, zoom: 150},
            %{x: 50, y: 101, zoom: 150},
            %{x: 50, y: 50, zoom: 99},
            %{x: 50, y: 50, zoom: 301},
            %{x: "20", y: 50, zoom: 150},
            %{x: 20.0, y: 50, zoom: 150},
            %{x: nil, y: 50, zoom: 150},
            %{x: 50, y: 50},
            %{"x" => 50, "y" => 50, "zoom" => 200},
            nil
          ] do
        assert {:error, :invalid} = Quiz.set_avatar_crop(c.id, bad), inspect(bad)
      end

      assert Repo.aggregate(CardAvatarCrop, :count) == 0
    end

    test "a card that does not exist is not found" do
      assert {:error, :not_found} = Quiz.set_avatar_crop(0, @crop)
      assert {:error, :not_found} = Quiz.set_avatar_crop(-5, @crop)
      assert {:error, :not_found} = Quiz.set_avatar_crop(card!().id + 1_000_000, @crop)
      assert {:error, :not_found} = Quiz.set_avatar_crop("1", @crop)
      assert {:error, :invalid} = Quiz.set_avatar_crop(0, %{x: 500, y: 0, zoom: 0})
    end

    test "the database refuses out-of-range values" do
      c = card!()

      for bad <- [%{x: 101, y: 0, zoom: 100}, %{x: 0, y: -1, zoom: 100}, %{x: 0, y: 0, zoom: 99}] do
        assert_raise Ecto.ConstraintError, fn ->
          Repo.insert!(struct!(CardAvatarCrop, Map.put(bad, :card_id, c.id)))
        end
      end
    end

    test "deleting the card deletes its crop" do
      c = card!()
      {:ok, _} = Quiz.set_avatar_crop(c.id, @crop)
      Repo.delete!(c)
      assert Repo.aggregate(CardAvatarCrop, :count) == 0
    end
  end

  describe "avatar_crops/2" do
    test "only card slugs with a stored row; bad slugs and pool slugs are ignored" do
      [a, b, c] = [card!(), card!(), card!()]
      {:ok, _} = Quiz.set_avatar_crop(a.id, @crop)
      {:ok, _} = Quiz.set_avatar_crop(c.id, %{x: 1, y: 2, zoom: 300})

      slugs = [
        Avatars.card_slug(a.id),
        Avatars.card_slug(b.id),
        Avatars.card_slug(c.id),
        "jinzo",
        "card-007",
        "card-",
        "nope",
        "",
        nil,
        Avatars.card_slug(a.id)
      ]

      assert Quiz.avatar_crops(slugs) == %{
               Avatars.card_slug(a.id) => @crop,
               Avatars.card_slug(c.id) => %{x: 1, y: 2, zoom: 300}
             }
    end

    test "defaults: true has every card slug" do
      [a, b] = [card!(), card!()]
      {:ok, _} = Quiz.set_avatar_crop(a.id, @crop)
      missing = Avatars.card_slug(b.id + 1_000_000)

      assert Quiz.avatar_crops(
               [Avatars.card_slug(a.id), Avatars.card_slug(b.id), missing, "jinzo"],
               defaults: true
             ) == %{
               Avatars.card_slug(a.id) => @crop,
               Avatars.card_slug(b.id) => Avatars.default_crop(),
               missing => Avatars.default_crop()
             }
    end

    test "an empty list is an empty map" do
      assert Quiz.avatar_crops([]) == %{}
      assert Quiz.avatar_crops(["jinzo"], defaults: true) == %{}
    end
  end

  test "avatar_cards_with_crops keeps the order and fills in the default" do
    f = format_fixture(%{"date" => "2005-04-01"})
    [a, b] = [card!(), card!()]
    {:ok, _} = Quiz.add_avatar_card(f.id, b.id)
    {:ok, _} = Quiz.add_avatar_card(f.id, a.id)
    {:ok, _} = Quiz.set_avatar_crop(a.id, @crop)

    assert [
             %{card: %Card{id: bid, name: bname}, crop: bcrop},
             %{card: %Card{id: aid}, crop: acrop}
           ] =
             Quiz.avatar_cards_with_crops(f.id)

    assert {bid, bname, bcrop} == {b.id, b.name, Avatars.default_crop()}
    assert {aid, acrop} == {a.id, @crop}
    # same cards as avatar_cards/1
    assert Enum.map(Quiz.avatar_cards(f.id), & &1.id) == [bid, aid]
  end
end
