defmodule MillenniumQuiz.GameTest do
  use ExUnit.Case, async: true

  alias MillenniumQuiz.Game
  alias MillenniumQuiz.Cards.{Card, CardText}
  alias MillenniumQuiz.Quiz.{Choice, Question, QuestionCard, Topic}

  @format %{id: 1, name: "Test", date: ~D[2005-04-01]}
  @no_shuffle [shuffle: &Function.identity/1]
  @topics %{"A" => {1, 0}, "B" => {2, 1}}

  defp question(id, topic, position) do
    {topic_id, topic_position} = @topics[topic]

    %Question{
      id: id,
      text: "Q#{id}",
      position: position,
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
      question(4, "B", 1)
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

    test "snapshots the damage from the position; new games carry no points" do
      damage = new_game().questions |> Map.new(&{&1.id, &1.damage})
      assert damage == %{3 => 100, 1 => 400, 2 => 100, 4 => 400}
      assert Enum.all?(new_game().questions, &is_nil(&1.points))
    end

    test "everyone starts with the same life points: 4000, or 8000 on request" do
      assert Enum.map(new_game().players, &{&1.lp, &1.eliminated_at}) == [
               {4000, nil},
               {4000, nil}
             ]

      game = new_game(start_lp: 8000)
      assert game.start_lp == 8000
      assert Enum.map(game.players, & &1.lp) == [8000, 8000]
      assert new_game(start_lp: "8000").start_lp == 8000
    end

    test "refuses other life points" do
      for lp <- [0, 1000, 6000, -4000, nil, "abc", 4000.0, "4000.0"] do
        assert {:error, :invalid_start_lp} =
                 Game.new(@format, ["Ann", "Bob"], questions(), start_lp: lp),
               inspect(lp)
      end
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
      assert Enum.map(game.players, & &1.lp) == [4000, 3600, 4000]
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
    # Ann chose Q3 and Q2 (100 each), Bob chose Q1 and Q4 (400 each); the
    # other player was wrong every time
    assert [{%{name: "Bob", lp: 3800}, 1}, {%{name: "Ann", lp: 3200}, 0}] =
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

  describe "the board of a question" do
    @board %{
      "rule" => "mr1_2",
      "turn" => 2,
      "phase" => "main1",
      "turn_player" => 1,
      "reveal_all" => false,
      "emz" => [nil, nil],
      "players" => []
    }

    defp board_game do
      card = %Card{
        id: 7,
        name: "Jinzo",
        password: 77_585_513,
        card_texts: [],
        texts: %{"en" => "T"}
      }

      boards = %{3 => %{board: @board, cards: [card]}}
      new_game(boards: boards)
    end

    test "is copied into the question; questions without one have none" do
      game = board_game()
      with_board = Enum.find(game.questions, &(&1.id == 3))
      assert with_board.board == @board
      assert %{name: "Jinzo", text: "T", id: 7} = with_board.board_cards["77585513"]

      for q <- game.questions, q.id != 3 do
        assert q.board == nil
        assert q.board_cards == %{}
      end

      assert Enum.all?(new_game().questions, &(&1.board == nil and &1.board_cards == %{}))
    end

    test "survives a JSON roundtrip" do
      game = board_game()
      json = game |> Game.to_map() |> Jason.encode!() |> Jason.decode!()
      assert Game.from_map(json) == game
    end

    test "a snapshot from before boards loads without one" do
      map = board_game() |> Game.to_map() |> Jason.encode!() |> Jason.decode!()

      old =
        update_in(map, ["questions"], fn qs ->
          Enum.map(qs, &Map.drop(&1, ["board", "board_cards"]))
        end)

      game = Game.from_map(old)
      assert Enum.all?(game.questions, &(&1.board == nil and &1.board_cards == %{}))
      assert game.phase == :choosing

      # and a null board, as a game that was saved by this version holds it
      nulls =
        update_in(map, ["questions"], fn qs ->
          Enum.map(qs, &Map.merge(&1, %{"board" => nil, "board_cards" => nil}))
        end)

      assert Enum.all?(
               Game.from_map(nulls).questions,
               &(&1.board == nil and &1.board_cards == %{})
             )
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

  describe "damage" do
    test "per position: 100, 400, 900, 1600, 2500, then 3000" do
      assert Enum.map(0..9, &Question.damage/1) ==
               [100, 400, 900, 1600, 2500, 3000, 3000, 3000, 3000, 3000]
    end
  end

  # One topic with `count` questions, damage 100, 400, 900...
  defp ladder(count) do
    for position <- 0..(count - 1), do: question(position + 1, "A", position)
  end

  defp ladder_game(count, opts \\ [], names \\ ["Ann", "Bob"]) do
    {:ok, game} = Game.new(@format, names, ladder(count), Keyword.merge(@no_shuffle, opts))
    game
  end

  # Plays the next question of the ladder; `picks` are in answer order.
  defp round_of(game, picks) do
    index = Enum.find_index(game.questions, &is_nil(&1.result))
    play(game, index, picks)
  end

  defp lps(game), do: Enum.map(game.players, & &1.lp)

  defp set_lp(game, lp) when is_integer(lp),
    do: %{game | players: Enum.map(game.players, &%{&1 | lp: lp})}

  defp set_lp(game, index, lp),
    do: %{game | players: List.update_at(game.players, index, &%{&1 | lp: lp})}

  describe "life points" do
    test "everyone right: nothing changes" do
      game = round_of(new_game(), [0, 0])
      assert game.phase == :revealed
      assert lps(game) == [4000, 4000]
    end

    test "everyone wrong: everyone takes the damage" do
      game = ladder_game(4, [], ~w(Ann Bob Cy)) |> round_of([1, 1, 1])
      assert lps(game) == [3900, 3900, 3900]
    end

    test "only those who were wrong lose the damage of the question" do
      game = ladder_game(4, [], ~w(Ann Bob Cy)) |> round_of([0, 1, 0])
      assert lps(game) == [4000, 3900, 4000]
      {:ok, game} = Game.next_round(game)
      # question two costs 400; Bob chooses now and answers first
      game = round_of(game, [0, 1, 1])
      assert lps(game) == [3600, 3900, 3600]
    end

    test "life points stop at 0, the player is out and the round is recorded" do
      game = ladder_game(8) |> set_lp(0, 50) |> round_of([1, 0])
      assert lps(game) == [0, 4000]
      assert Enum.map(game.players, & &1.eliminated_at) == [1, nil]
    end

    test "lp_before_reveal/2 is the start LP minus the earlier wrong answers" do
      # Ann answers wrong on the first question (100), Bob is right
      game = ladder_game(8) |> round_of([1, 0])
      assert Game.lp_before_reveal(game, 0) == 4000
      assert Game.lp_before_reveal(game, 1) == 4000

      {:ok, game} = Game.next_round(game)
      # second question (400): Bob answers first and is right, Ann wrong and out at 50
      game = game |> set_lp(0, 50) |> round_of([0, 1])
      assert lps(game) == [0, 4000]
      assert Game.lp_before_reveal(game, 0) == 3900
      assert Game.lp_before_reveal(game, 1) == 4000
    end

    test "an eliminated player is skipped as chooser and in the answering order" do
      game = ladder_game(10, [], ~w(Ann Bob Cy)) |> set_lp(1, 50)
      # Ann chooses, Bob (answering second) is wrong and out
      game = round_of(game, [0, 1, 0])
      assert Enum.at(game.players, 1).eliminated_at == 1
      assert Game.answer_order(game) == [0, 1, 2]
      {:ok, game} = Game.next_round(game)

      # the turn passes over Bob to Cy
      assert game.phase == :choosing
      refute Game.alive?(game, 1)
      assert Game.chooser_index(game) == 2
      assert Game.answer_order(game) == [2, 0]

      # and the rotation keeps skipping him
      choosers =
        Enum.scan(1..4, game, fn _, game ->
          game = round_of(game, [0, 0])
          {:ok, game} = Game.next_round(game)
          game
        end)
        |> Enum.map(&Game.chooser_index/1)

      assert choosers == [0, 2, 0, 2]
    end

    test "the chooser being eliminated this round still sees the whole round" do
      game = ladder_game(8) |> set_lp(0, 100) |> round_of([1, 0])
      assert game.phase == :revealed
      assert Game.answer_order(game) == [0, 1]
      assert lps(game) == [0, 4000]
      assert [%{eliminated_at: 1}, %{eliminated_at: nil}] = game.players
    end

    test "a dead chooser hands the turn on in a game of three" do
      game = ladder_game(8, [], ~w(Ann Bob Cy)) |> set_lp(0, 100) |> round_of([1, 0, 0])
      {:ok, game} = Game.next_round(game)
      assert Game.chooser_index(game) == 1
      assert Game.answer_order(game) == [1, 2]
    end

    test "two players and one dies: the game ends although the board is not empty" do
      game = ladder_game(8) |> set_lp(1, 50) |> round_of([0, 1])
      assert lps(game) == [4000, 0]
      assert Game.over?(game)
      {:ok, game} = Game.next_round(game)
      assert game.phase == :finished
      assert Enum.any?(game.questions, &is_nil(&1.result))
      assert [{%{name: "Ann"}, 0}] = Game.winners(game)
      refute Game.draw?(game)
    end

    test "three players, two die together: the survivor wins, no draw" do
      game = ladder_game(8, [], ~w(Ann Bob Cy)) |> set_lp(100) |> round_of([1, 0, 1])
      {:ok, game} = Game.next_round(game)
      assert game.phase == :finished
      assert [{%{name: "Bob"}, 1}] = Game.winners(game)
      refute Game.draw?(game)
      # the two eliminated together share second place
      assert Enum.map(Game.places(game), &elem(&1, 2)) == [1, 2, 2]
    end

    test "the last players dropping to 0 in the same round is a draw" do
      game = ladder_game(8, [], ~w(Ann Bob Cy)) |> set_lp(100) |> round_of([1, 1, 1])
      assert lps(game) == [0, 0, 0]
      {:ok, game} = Game.next_round(game)
      assert game.phase == :finished
      assert Game.draw?(game)
      assert length(Game.winners(game)) == 3
      assert Enum.map(Game.places(game), &elem(&1, 2)) == [1, 1, 1]
    end

    test "a draw between the last two, after a third player was out earlier" do
      game = ladder_game(8, [], ~w(Ann Bob Cy)) |> set_lp(2, 100) |> round_of([0, 0, 1])
      {:ok, game} = Game.next_round(game)
      assert Game.answer_order(game) == [1, 0]

      game = game |> set_lp(0, 100) |> set_lp(1, 100) |> round_of([1, 1])
      {:ok, game} = Game.next_round(game)
      assert game.phase == :finished
      assert Game.draw?(game)
      assert [{%{name: "Ann"}, 0}, {%{name: "Bob"}, 1}] = Game.winners(game)
      assert Enum.map(Game.places(game), &{elem(&1, 1), elem(&1, 2)}) == [{0, 1}, {1, 1}, {2, 3}]
    end

    test "the ranking: survivors by life points, then the latest eliminated first" do
      game = ladder_game(8, [], ~w(Ann Bob Cy Di))
      [a, b, c, d] = game.players

      players = [
        %{a | lp: 1500},
        %{b | lp: 0, eliminated_at: 3},
        %{c | lp: 2500},
        %{d | lp: 0, eliminated_at: 5}
      ]

      game = %{game | players: players, phase: :finished}
      assert Enum.map(Game.standings(game), &elem(&1, 1)) == [2, 0, 3, 1]
      assert Enum.map(Game.places(game), &elem(&1, 2)) == [1, 2, 3, 4]
      refute Game.draw?(game)

      # equal life points share a place, the next one skips
      game = %{game | players: List.update_at(players, 0, &%{&1 | lp: 2500})}
      assert Enum.map(Game.places(game), &elem(&1, 2)) == [1, 1, 3, 4]
      assert length(Game.winners(game)) == 2
      refute Game.draw?(game)
    end

    test "finishing early keeps the life points and ranks the survivors" do
      game = round_of(new_game(), [0, 1])
      {:ok, game} = Game.next_round(game)
      {:ok, game} = Game.finish(game)
      assert game.phase == :finished
      assert [{%{name: "Ann", lp: 4000}, 0}, {%{name: "Bob", lp: 3900}, 1}] = Game.standings(game)
      assert [{%{name: "Ann"}, 0}] = Game.winners(game)
      assert Game.chooser_index(game) == nil
    end

    test "Level Up! shows the damage of each column's next question" do
      game = new_game(mode: :ascending)
      assert Game.next_damage(game, 0) == 100
      assert Game.next_damage(game, 1) == 100
      game = play(game, 0, [0, 0])
      {:ok, game} = Game.next_round(game)
      assert Game.next_damage(game, 0) == 400
      game = play(game, 1, [0, 0])
      {:ok, game} = Game.next_round(game)
      assert Game.next_damage(game, 0) == nil
      assert Game.next_damage(game, 1) == 100
    end

    test "life points are never negative nor above the start, whatever happens" do
      :rand.seed(:exsss, {11, 22, 33})

      for start_lp <- [4000, 8000], _ <- 1..30 do
        count = Enum.random(3..12)
        names = Enum.take(~w(Ann Bob Cy Di), Enum.random(2..4))
        game = ladder_game(count, [start_lp: start_lp], names)

        final =
          Enum.reduce_while(1..count, game, fn _, game ->
            picks = for _ <- Game.answer_order(game), do: Enum.random([0, 1])
            game = round_of(game, picks)

            assert Enum.all?(game.players, &(&1.lp in 0..start_lp))
            assert Enum.all?(game.players, &(&1.lp == 0 == (&1.eliminated_at != nil)))
            {:ok, game} = Game.next_round(game)
            if game.phase == :finished, do: {:halt, game}, else: {:cont, game}
          end)

        alive = Enum.count(final.players, &(&1.lp > 0))
        assert final.phase == :finished or alive > 1
        assert [{_, _, 1} | _] = Game.places(final)
      end
    end

    test "survives a JSON roundtrip with eliminated players" do
      game = ladder_game(8) |> set_lp(1, 50) |> round_of([0, 1])
      json = game |> Game.to_map() |> Jason.encode!() |> Jason.decode!()
      assert %{"start_lp" => 4000} = json
      loaded = Game.from_map(json)
      assert loaded == game
      assert Enum.map(loaded.players, & &1.eliminated_at) == [nil, 1]
      assert hd(loaded.questions).damage == 100
    end
  end

  describe "snapshots of score games (before the life points)" do
    # A snapshot as the score rules wrote it.
    defp score_snapshot do
      %{
        "format_id" => 1,
        "format_name" => "Old",
        "format_date" => "2005-04-01",
        "mode" => "free",
        "players" => [
          %{"name" => "Ann", "score" => 30, "avatar" => "yugi"},
          %{"name" => "Bob", "score" => 50, "avatar" => nil}
        ],
        "topics" => ["A"],
        "questions" => [
          %{
            "id" => 1,
            "topic" => "A",
            "column" => 0,
            "text" => "Q1",
            "points" => 10,
            "choices" => ["right", "wrong"],
            "correct" => 0,
            "cards" => [],
            "result" => %{"chooser" => 0, "picks" => [0, 1]}
          },
          %{
            "id" => 2,
            "topic" => "A",
            "column" => 0,
            "text" => "Q2",
            "points" => 20,
            "choices" => ["right", "wrong"],
            "correct" => 0,
            "cards" => [],
            "result" => nil
          }
        ],
        "round" => 2,
        "turn_order" => [0, 1],
        "turn_index" => 1,
        "current" => nil,
        "picks" => [nil, nil],
        "answered" => 0,
        "phase" => "choosing"
      }
    end

    test "open as finished and read-only, ranked by their score" do
      game = Game.from_map(score_snapshot())
      assert game.phase == :finished
      assert game.start_lp == nil
      assert [%{name: "Ann", score: 30, lp: nil}, %{name: "Bob", score: 50}] = game.players
      assert Enum.map(Game.standings(game), &elem(&1, 1)) == [1, 0]
      assert [{%{name: "Bob"}, 1}] = Game.winners(game)
      refute Game.draw?(game)
      assert [%{points: 10, damage: nil}, %{points: 20}] = game.questions

      assert {:error, :not_choosing} = Game.choose(game, 1)
      assert {:error, :not_answering} = Game.answer(game, 0)
      assert {:error, :not_revealed} = Game.next_round(game)
    end

    test "a score game stays loadable after being saved again" do
      game = Game.from_map(score_snapshot())
      json = game |> Game.to_map() |> Jason.encode!() |> Jason.decode!()
      assert Game.from_map(json) == game
    end
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
