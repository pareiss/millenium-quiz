defmodule MillenniumQuiz.Quiz.AvatarSetsTest do
  # Deletes all formats (the test database holds a seeded one): not async.
  use MillenniumQuiz.DataCase, async: false

  @moduletag :capture_log

  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{Avatars, CardSourcesStub, Quiz, Release}
  alias MillenniumQuiz.Cards.Card
  alias MillenniumQuiz.Quiz.{AvatarSets, CardAvatarCrop, Format, FormatAvatarCard}

  @edison ~D[2010-04-24]

  setup do
    CardSourcesStub.stub!()
    Repo.delete_all(Format)
    :ok
  end

  defp pool_card!(%{password: password, name: name}, attrs \\ %{}) do
    Repo.insert!(
      struct!(
        Card,
        Map.merge(
          %{
            name: name,
            password: password,
            tcg_release_date: ~D[2002-03-08],
            fetched_at: DateTime.utc_now(:second)
          },
          attrs
        )
      )
    )
  end

  defp fill_pool!(date, skip \\ []) do
    for m <- Avatars.set_for(date), m.password not in skip, do: pool_card!(m)
  end

  defp edison!, do: format_fixture(%{"name" => "Edison", "date" => Date.to_iso8601(@edison)})

  test "the sets in code are the three formats' and need no other data" do
    assert Enum.sort(Avatars.set_dates(), Date) == [
             ~D[2005-04-01],
             ~D[2010-04-24],
             ~D[2011-09-01]
           ]

    assert [_ | _] = Avatars.set_for(@edison)
    assert Avatars.set_for(~D[2020-01-01]) == []
    assert Avatars.set_for(nil) == []
    assert Avatars.face_crop({135, 45, 190}) == %{x: 37, y: 22, zoom: 300}
    # a big face is not zoomed beyond what fits, and the crop is valid
    for date <- Avatars.set_dates(), m <- Avatars.set_for(date) do
      crop = Avatars.face_crop(m.face)
      assert crop.zoom in 100..300 and crop.x in 0..100 and crop.y in 0..100
    end
  end

  test "adopts a set whose cards are in the pool: same order, crops, and games use the cards" do
    format = edison!()
    fill_pool!(@edison)

    assert [%{format: "Edison", status: :adopted, missing: []}] = AvatarSets.adopt(fetch: false)

    set = Avatars.set_for(@edison)
    assert Enum.map(Quiz.avatar_cards(format.id), & &1.password) == Enum.map(set, & &1.password)

    for %{card: card, crop: crop} <- Quiz.avatar_cards_with_crops(format.id) do
      monster = Enum.find(set, &(&1.password == card.password))
      assert crop == Avatars.face_crop(monster.face)
    end

    pool = Avatars.pool(Quiz.get_format!(format.id))
    assert pool == Enum.map(Quiz.avatar_cards(format.id), &Avatars.card_slug(&1.id))
    # a game saved with a built-in picture still has its image
    assert Avatars.path("jinzo") == "/images/avatars/jinzo.jpg"
  end

  test "is idempotent and never touches a format that has cards of its own" do
    format = edison!()
    fill_pool!(@edison)
    assert [%{status: :adopted}] = AvatarSets.adopt(fetch: false)
    rows = Repo.aggregate(FormatAvatarCard, :count)
    crops = Repo.aggregate(CardAvatarCrop, :count)

    assert [%{status: :already}] = AvatarSets.adopt(fetch: false)
    assert Repo.aggregate(FormatAvatarCard, :count) == rows
    assert Repo.aggregate(CardAvatarCrop, :count) == crops

    # an admin's list of one card stays one card
    [first | _] = Quiz.avatar_cards(format.id)

    for card <- tl(Quiz.avatar_cards(format.id)), do: Quiz.remove_avatar_card(format.id, card.id)

    assert [%{status: :already}] = AvatarSets.adopt(fetch: false)
    assert Enum.map(Quiz.avatar_cards(format.id), & &1.id) == [first.id]
  end

  test "with an empty pool nothing changes and nothing is fetched when fetch is off" do
    edison!()
    assert [%{status: :incomplete, missing: missing}] = AvatarSets.adopt(fetch: false)
    assert length(missing) == length(Avatars.set_for(@edison))
    assert Repo.aggregate(FormatAvatarCard, :count) == 0
    assert Repo.aggregate(CardAvatarCrop, :count) == 0
  end

  test "a card that cannot be fetched leaves the whole set alone and is named" do
    format = edison!()
    [gone | _] = Avatars.set_for(@edison)
    fill_pool!(@edison, [gone.password])

    # the stub knows none of the set's cards: the fetch fails, nothing breaks
    assert [%{status: :incomplete, missing: [name]}] = AvatarSets.adopt(pause_ms: 0)
    assert name == gone.name
    assert Quiz.avatar_cards(format.id) == []
    assert Repo.aggregate(FormatAvatarCard, :count) == 0
    # a few cards short, the code's set is still what games use
    assert Avatars.pool(Quiz.get_format!(format.id)) == Avatars.for_format(@edison)
  end

  test "a card newer than the format's date leaves the set alone" do
    format = edison!()
    [late | rest] = Avatars.set_for(@edison)
    pool_card!(late, %{tcg_release_date: ~D[2020-01-01]})
    for m <- rest, do: pool_card!(m)

    assert [%{status: :incomplete, missing: [], late: [name]}] = AvatarSets.adopt(fetch: false)
    assert name == late.name
    assert Quiz.avatar_cards(format.id) == []
  end

  test "every late card is named, next to the missing ones" do
    format = edison!()
    [missing, late1, late2 | rest] = Avatars.set_for(@edison)
    pool_card!(late1, %{tcg_release_date: ~D[2020-01-01]})
    pool_card!(late2, %{tcg_release_date: ~D[2011-01-01]})
    for m <- rest, do: pool_card!(m)

    assert [%{status: :incomplete, missing: [m], late: late}] = AvatarSets.adopt(fetch: false)
    assert m == missing.name
    assert Enum.sort(late) == Enum.sort([late1.name, late2.name])
    assert Quiz.avatar_cards(format.id) == []
  end

  test "fetches a card the pool lacks, one at a time, and adopts the set" do
    format = edison!()
    [first | _] = set = Avatars.set_for(@edison)
    fill_pool!(@edison, [first.password])

    CardSourcesStub.stub_with_card!(%{
      password: first.password,
      name: first.name,
      date: "2002-03-08"
    })

    assert [%{status: :adopted, missing: [], late: []}] = AvatarSets.adopt(pause_ms: 0)
    assert Enum.map(Quiz.avatar_cards(format.id), & &1.password) == Enum.map(set, & &1.password)
    assert %{} = Quiz.avatar_crop(hd(Quiz.avatar_cards(format.id)).id)
  end

  test "a card that was fetched but came out after the format's date is reported as late" do
    format = edison!()
    [first | _] = Avatars.set_for(@edison)
    fill_pool!(@edison, [first.password])

    CardSourcesStub.stub_with_card!(%{
      password: first.password,
      name: first.name,
      date: "2020-01-01"
    })

    assert [%{status: :incomplete, missing: [], late: [name]}] = AvatarSets.adopt(pause_ms: 0)
    assert name == first.name
    assert Quiz.avatar_cards(format.id) == []
  end

  test "a picture an admin adds while the cards are fetched is not buried under the set" do
    format = edison!()
    [first | _] = Avatars.set_for(@edison)
    fill_pool!(@edison, [first.password])
    own = pool_card!(%{password: 99_999_001, name: "Own pick"})

    CardSourcesStub.stub_with_card!(%{
      password: first.password,
      name: first.name,
      date: "2002-03-08",
      before_fetch: fn -> {:ok, _} = Quiz.add_avatar_card(format.id, own.id) end
    })

    assert [%{status: :already, missing: [], late: []}] = AvatarSets.adopt(pause_ms: 0)
    assert Enum.map(Quiz.avatar_cards(format.id), & &1.id) == [own.id]
  end

  test "Release.adopt_avatar_sets/0 and mix avatars.adopt print the report" do
    edison!()
    fill_pool!(@edison)

    out = ExUnit.CaptureIO.capture_io(fn -> Release.adopt_avatar_sets() end)
    assert out =~ "Edison: the built-in profile pictures are now the format's own"

    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    Mix.Tasks.Avatars.Adopt.run([])
    assert_received {:mix_shell, :info, [line]}
    assert line =~ "Edison: has profile pictures of its own"
  end

  test "a crop that is stored already is kept" do
    format = edison!()
    cards = fill_pool!(@edison)
    first = hd(cards)
    {:ok, _} = Quiz.set_avatar_crop(first.id, %{x: 10, y: 90, zoom: 120})

    assert [%{status: :adopted}] = AvatarSets.adopt(fetch: false)
    assert Quiz.avatar_crop(first.id) == %{x: 10, y: 90, zoom: 120}
    assert length(Quiz.avatar_cards(format.id)) == length(cards)
  end

  test "formats without a set date, or no format at all, are not touched" do
    assert AvatarSets.adopt(fetch: false) == []
    format_fixture(%{"date" => "2020-01-01"})
    assert AvatarSets.adopt(fetch: false) == []
  end

  test "the adopted cards are in the backup with their crops" do
    edison!()
    fill_pool!(@edison)
    AvatarSets.adopt(fetch: false)

    assert [%{"avatar_cards" => cards}] = Quiz.Export.build()["formats"]
    assert length(cards) == length(Avatars.set_for(@edison))
    assert Enum.all?(cards, &is_map(&1["crop"]))
  end

  test "the report says what happened" do
    assert [_] = Release.adopt_report([])

    lines =
      Release.adopt_report([
        %{format: "A", status: :adopted, missing: []},
        %{format: "B", status: :already, missing: []},
        %{format: "C", status: :incomplete, missing: ["Jinzo"], late: []},
        %{format: "D", status: :incomplete, missing: [], late: ["Spore"]}
      ])

    assert Enum.at(lines, 0) =~ "A: the built-in"
    assert Enum.at(lines, 1) =~ "left alone"
    assert Enum.at(lines, 2) =~ "could not get Jinzo. Run it again."
    assert Enum.at(lines, 3) =~ "Released after the format's date"
    assert Enum.at(lines, 3) =~ "Spore"
    refute Enum.at(lines, 3) =~ "Run it again"
  end
end
