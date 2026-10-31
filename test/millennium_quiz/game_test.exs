defmodule MillenniumQuiz.GameTest do
  use ExUnit.Case, async: true

  alias MillenniumQuiz.Game
  alias MillenniumQuiz.Cards.{Card, CardText}
  alias MillenniumQuiz.Quiz.{Choice, Question, QuestionCard, Topic}

  @format %{id: 1, name: "Test", date: ~D[2005-04-01]}
  @no_shuffle [shuffle: &Function.identity/1]
  @topics %{"A" => {1, 0}, "B" => {2, 1}}

  defp question(id, topic, position, opts \\ []) do
    {topic_id, topic_position} = @topics[topic]

    %Question{
      id: id,
      text: "Q#{id}",
      position: position,
      points: opts[:points],
      topic_id: topic_id,
      topic: %Topic{id: topic_id, name: topic, position: topic_position},
      choices: [%Choice{text: "right", correct: true}, %Choice{text: "wrong", correct: false}]
    }
  end

  defp questions do
    [
      question(1, "A", 1),
      question(2, "B", 0),
      question(3, "A", 0),
      question(4, "B", 1, points: 99)
    ]
  end

  defp new_game(opts \\ [], names \\ ["Ann", "Bob"]) do
    {:ok, game} = Game.new(@format, names, questions(), Keyword.merge(@no_shuffle, opts))
    game
  end

  # Chooses question `index`; `choices` are the picks in answer order.
  defp play(game, index, choices) do
    {:ok, game} = Game.choose(game, index)

    Enum.reduce(choices, game, fn choice, game ->
      {:ok, game} = Game.answer(game, choice)
      game
    end)
  end

  describe "new/4" do
    test "validates players, questions and mode" do
      assert {:error, :invalid_player_count} = Game.new(@format, ["Solo"], questions())
      assert {:error, :invalid_player_count} = Game.new(@format, ~w(a b c d e), questions())
      assert {:error, :blank_player_name} = Game.new(@format, ["Ann", "  "], questions())

      assert {:error, :player_name_too_long} =
               Game.new(@format, ["Ann", String.duplicate("x", 25)], questions())

      assert {:ok, _} = Game.new(@format, ["Ann", String.duplicate("x", 24)], questions())
      assert {:error, :no_questions} = Game.new(@format, ["Ann", "Bob"], [])

      assert {:error, :invalid_mode} =
               Game.new(@format, ["Ann", "Bob"], questions(), mode: "nope")
    end

    test "builds the board: topics as columns, each from easiest to hardest" do
      game = new_game()
      assert game.phase == :choosing
      assert game.topics == ["A", "B"]
      assert Enum.map(game.questions, &{&1.id, &1.column}) == [{3, 0}, {1, 0}, {2, 1}, {4, 1}]
    end

    test "snapshots points: default from position, override wins" do
      points = new_game().questions |> Map.new(&{&1.id, &1.points})
      assert points == %{3 => 10, 1 => 20, 2 => 10, 4 => 99}
    end

    test "accepts the mode as a string" do
      assert new_game(mode: "ascending").mode == :ascending
      assert new_game().mode == :free
    end
  end

  describe "Heart of the Cards (free)" do
    test "the chooser picks any open question, then everyone answers, chooser first" do
      game = new_game([shuffle: &Enum.reverse/1], ["Ann", "Bob", "Cid"])
      assert game.turn_order == [2, 1, 0]
      assert Game.current_player(game).name == "Cid"

      # the hardest question of topic B right away
      {:ok, game} = Game.choose(game, 3)
      assert Game.current_player(game).name == "Cid"
      {:ok, game} = Game.answer(game, 0)
      assert game.phase == :answering
      assert Game.current_player(game).name == "Bob"
      {:ok, game} = Game.answer(game, 1)
      {:ok, game} = Game.answer(game, 0)

      assert game.phase == :revealed
      assert Game.correct?(game, 2)
      refute Game.correct?(game, 1)
      assert Enum.map(game.players, & &1.score) == [99, 0, 99]
      assert Game.correct_count(Enum.at(game.questions, 3)) == 2

      {:ok, game} = Game.next_round(game)
      assert game.phase == :choosing
      assert game.picks == [nil, nil, nil]
      assert Game.current_player(game).name == "Bob"
      assert {:error, :invalid_question} = Game.choose(game, 3)

      # Bob chooses, so Bob answers first and Cid answers last
      {:ok, game} = Game.choose(game, 1)
      assert Game.answer_order(game) == [1, 0, 2]
      assert Game.current_player(game).name == "Bob"
    end

    test "rejects choices that do not exist and actions out of phase" do
      game = new_game()
      assert {:error, :not_answering} = Game.answer(game, 0)
      assert {:error, :invalid_question} = Game.choose(game, 9)
      {:ok, game} = Game.choose(game, 0)
      assert {:error, :not_choosing} = Game.choose(game, 1)
      assert {:error, :invalid_choice} = Game.answer(game, 5)
      assert {:error, :not_revealed} = Game.next_round(game)
    end
  end

  describe "Level Up! (ascending)" do
    test "only the easiest open question of a topic can be chosen" do
      game = new_game(mode: :ascending)
      assert Game.next_in_column(game, 0) == 0
      refute Game.choosable?(game, 1)
      assert {:error, :invalid_question} = Game.choose(game, 1)

      game = play(game, 0, [0, 0])
      {:ok, game} = Game.next_round(game)
      assert Game.next_in_column(game, 0) == 1
      assert Game.choosable?(game, 1)
    end
  end

  test "choosing rotates and the game finishes when the board is empty" do
    game =
      Enum.reduce(0..3, new_game(), fn index, game ->
        assert Game.current_player_index(game) == rem(index, 2)
        # the chooser is right, the other player is wrong
        game = play(game, index, [0, 1])
        {:ok, game} = Game.next_round(game)
        game
      end)

    assert game.phase == :finished
    # Ann chose Q3 (10) and Q2 (10), Bob chose Q1 (20) and Q4 (99)
    assert [{%{name: "Bob", score: 119}, 1}, {%{name: "Ann", score: 20}, 0}] =
             Game.standings(game)
  end

  test "survives a JSON roundtrip" do
    game = play(new_game(mode: :ascending), 0, [1])
    json = game |> Game.to_map() |> Jason.encode!() |> Jason.decode!()
    assert Game.from_map(json) == game
  end

  test "cards are snapshotted as printed on the format's date, with their details" do
    card = %Card{
      id: 7,
      name: "Plain Card",
      kind: "Monster",
      frame_type: "xyz_pendulum",
      monster_type_line: "Dragon / Xyz / Pendulum / Effect",
      attribute: "DARK",
      rank: 7,
      atk: "3000",
      def: "?",
      pendulum_scale: 4,
      pendulum_texts: %{"en" => "Once per turn: draw 1 card."},
      card_texts: [
        %CardText{
          language: "en",
          version: 0,
          text: "Old.",
          set: "Old Set",
          released_on: ~D[2004-01-01]
        },
        %CardText{
          language: "en",
          version: 1,
          text: "New.",
          set: "New Set",
          released_on: ~D[2010-01-01]
        }
      ]
    }

    [first | rest] = questions()

    {:ok, game} =
      Game.new(
        @format,
        ["Ann", "Bob"],
        [%{first | question_cards: [%QuestionCard{card: card}]} | rest],
        @no_shuffle
      )

    assert [snapshot] = Enum.find(game.questions, &(&1.id == 1)).cards

    assert snapshot == %{
             id: 7,
             name: "Plain Card",
             text: "Old.",
             set: "Old Set",
             kind: "Monster",
             property: nil,
             frame_type: "xyz_pendulum",
             monster_type_line: "Dragon / Xyz / Pendulum / Effect",
             attribute: "DARK",
             level: nil,
             rank: 7,
             link_arrows: [],
             atk: "3000",
             def: "?",
             pendulum_scale: 4,
             pendulum_text: "Once per turn: draw 1 card.",
             owner: nil
           }

    json = game |> Game.to_map() |> Jason.encode!() |> Jason.decode!()
    assert Game.from_map(json) == game
  end

  test "the owner of a card is snapshotted; older snapshots and odd values load without one" do
    card = %Card{id: 7, name: "Plain Card", card_texts: []}
    [first | rest] = questions()

    {:ok, game} =
      Game.new(
        @format,
        ["Ann", "Bob"],
        [
          %{
            first
            | question_cards: [
                %QuestionCard{card: card, owner: 2},
                %QuestionCard{card: %{card | id: 8, name: "Other"}, owner: nil}
              ]
          }
          | rest
        ],
        @no_shuffle
      )

    assert [%{owner: 2}, %{owner: nil}] = Enum.find(game.questions, &(&1.id == 1)).cards

    map = game |> Game.to_map() |> Jason.encode!() |> Jason.decode!()
    assert Game.from_map(map) == game

    # a snapshot from before owners has no "owner" key; a wrong value is no owner
    strip = fn value ->
      update_in(map, ["questions"], fn qs ->
        Enum.map(qs, fn q ->
          Map.update!(q, "cards", fn cards ->
            Enum.map(
              cards,
              &if(value == :drop, do: Map.delete(&1, "owner"), else: Map.put(&1, "owner", value))
            )
          end)
        end)
      end)
    end

    for value <- [:drop, 3, "1", 0] do
      cards = Enum.find(Game.from_map(strip.(value)).questions, &(&1.id == 1)).cards
      assert Enum.all?(cards, &(&1.owner == nil)), inspect(value)
    end
  end

  test "the submitter name is kept in a snapshot; older snapshots load without it" do
    map = new_game() |> Game.to_map() |> Jason.encode!() |> Jason.decode!()

    with_name =
      update_in(map, ["questions"], fn [q | rest] ->
        [Map.put(q, "submitted_by", "Yugi") | rest]
      end)

    assert hd(Game.from_map(with_name).questions).submitted_by == "Yugi"

    old =
      update_in(map, ["questions"], fn qs -> Enum.map(qs, &Map.delete(&1, "submitted_by")) end)

    assert Enum.all?(Game.from_map(old).questions, &(&1.submitted_by == nil))
  end

  test "cards from older snapshots load without their details" do
    map = new_game() |> Game.to_map() |> Jason.encode!() |> Jason.decode!()
    old_card = %{"name" => "Monster Reborn", "text" => "Revive.", "set" => nil}

    map =
      update_in(map, ["questions"], fn [q | rest] -> [Map.put(q, "cards", [old_card]) | rest] end)

    assert [card] = hd(Game.from_map(map).questions).cards

    assert %{id: nil, name: "Monster Reborn", text: "Revive.", frame_type: nil, link_arrows: []} =
             card
  end

  test "snapshots from before card links load with their plain text" do
    map = new_game() |> Game.to_map() |> Jason.encode!() |> Jason.decode!()

    map =
      update_in(map, ["questions"], fn [q | rest] ->
        [Map.put(q, "text", "Plain [sic]") | rest]
      end)

    game = Game.from_map(map)
    assert hd(game.questions).text == "Plain [sic]"
    assert Game.from_map(map |> Jason.encode!() |> Jason.decode!()) == game
  end

  test "snapshots from before formats keep their category name" do
    map = new_game() |> Game.to_map() |> Jason.encode!() |> Jason.decode!()

    legacy =
      map
      |> Map.drop(["format_id", "format_name", "format_date"])
      |> Map.merge(%{"category_id" => 1, "category_name" => "Old"})

    assert %Game{format_id: 1, format_name: "Old", format_date: nil} = Game.from_map(legacy)
    assert Game.from_map(map).format_date == ~D[2005-04-01]
  end

  test "every player gets a different avatar that survives saving" do
    game = new_game([], ~w(Ann Bob Cy Di))
    avatars = Enum.map(game.players, & &1.avatar)

    assert Enum.all?(avatars, &MillenniumQuiz.Avatars.name/1)
    assert length(Enum.uniq(avatars)) == 4

    saved = game |> Game.to_map() |> Jason.encode!() |> Jason.decode!() |> Game.from_map()
    assert Enum.map(saved.players, & &1.avatar) == avatars
  end

  test "the avatars come from the format's set, else from the default pool" do
    for date <- [~D[2010-04-24], ~D[2005-04-01], ~D[2011-09-01]] do
      {:ok, game} =
        Game.new(%{@format | date: date}, ~w(Ann Bob Cy Di), questions(),
          shuffle: &Enum.shuffle/1
        )

      avatars = Enum.map(game.players, & &1.avatar)
      assert length(Enum.uniq(avatars)) == 4
      assert avatars -- MillenniumQuiz.Avatars.for_format(date) == []
    end

    default = MillenniumQuiz.Avatars.default_slugs()

    {:ok, game} =
      Game.new(%{@format | date: ~D[2007-01-01]}, ~w(Ann Bob Cy Di), questions(),
        shuffle: &Enum.shuffle/1
      )

    assert Enum.all?(game.players, &(&1.avatar in default))
  end

  describe "chosen avatars" do
    @set MillenniumQuiz.Avatars.for_format(~D[2005-04-01])

    defp avatars_of(opts, names \\ ~w(Ann Bob Cy)) do
      case Game.new(@format, names, questions(), Keyword.merge(@no_shuffle, opts)) do
        {:ok, game} -> Enum.map(game.players, & &1.avatar)
        error -> error
      end
    end

    test "chosen ones are kept, the rest differ from them" do
      [a, b, c, d | _] = @set
      assert avatars_of(avatars: [c, a, b]) == [c, a, b]
      assert avatars_of(avatars: [c, nil, nil]) == [c, a, b]
      assert avatars_of(avatars: [nil, d]) == [a, d, b]
      assert avatars_of(avatars: ["", c]) == [a, c, b]
      assert avatars_of(avatars: []) == [a, b, c]
    end

    test "random ones never take a chosen one" do
      [a | _] = @set

      for _ <- 1..20 do
        {:ok, game} =
          Game.new(@format, ~w(Ann Bob Cy Di), questions(), avatars: [nil, nil, nil, a])

        avatars = Enum.map(game.players, & &1.avatar)
        assert List.last(avatars) == a
        assert length(Enum.uniq(avatars)) == 4
      end
    end

    test "an avatar must be in the pool, and only once" do
      [a | _] = @set
      assert avatars_of(avatars: ["jinzo", nil]) == {:error, :invalid_avatar}
      assert avatars_of(avatars: ["card-5", nil]) == {:error, :invalid_avatar}
      assert avatars_of(avatars: [5, nil]) == {:error, :invalid_avatar}
      assert avatars_of(avatars: "x") == {:error, :invalid_avatar}
      assert avatars_of(avatars: [a, nil, nil, nil]) == {:error, :invalid_avatar}
      assert avatars_of(avatars: [a, a]) == {:error, :duplicate_avatars}
    end

    test "a format with avatar cards uses them, and a card slug survives saving" do
      format =
        Map.put(@format, :avatar_cards, [
          %{card_id: 11},
          %{card_id: 12},
          %{card_id: 13},
          %{card_id: 14}
        ])

      {:ok, game} =
        Game.new(format, ~w(Ann Bob), questions(),
          avatars: ["card-13", nil],
          shuffle: &Function.identity/1
        )

      assert Enum.map(game.players, & &1.avatar) == ["card-13", "card-11"]

      saved = game |> Game.to_map() |> Jason.encode!() |> Jason.decode!() |> Game.from_map()
      assert Enum.map(saved.players, & &1.avatar) == ["card-13", "card-11"]

      assert {:error, :invalid_avatar} =
               Game.new(format, ~w(Ann Bob), questions(), avatars: [hd(@set), nil])
    end

    test "a snapshot with an old slug still loads" do
      map = new_game() |> Game.to_map() |> Jason.encode!() |> Jason.decode!()
      assert [%{avatar: avatar}, _] = Game.from_map(map).players
      assert MillenniumQuiz.Avatars.name(avatar)
    end
  end

  test "games saved before the avatars have none" do
    map = new_game() |> Game.to_map() |> Jason.encode!() |> Jason.decode!()
    old = update_in(map["players"], fn ps -> Enum.map(ps, &Map.delete(&1, "avatar")) end)

    assert [%{avatar: nil}, %{avatar: nil}] = Game.from_map(old).players
  end

  test "snapshots from before the board modes open as finished" do
    legacy = %{
      "format_id" => 1,
      "format_name" => "Old",
      "players" => [%{"name" => "Ann", "score" => 10}],
      "questions" => [%{"topic" => "A"}],
      "round" => 1,
      "turn_order" => [0],
      "phase" => "answering"
    }

    assert %Game{phase: :finished, players: [%{name: "Ann", score: 10}]} = Game.from_map(legacy)
  end
end
