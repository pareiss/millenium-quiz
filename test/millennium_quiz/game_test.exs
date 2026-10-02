defmodule MillenniumQuiz.GameTest do
  use ExUnit.Case, async: true

  alias MillenniumQuiz.Game
  alias MillenniumQuiz.Quiz.{Choice, Question, Topic}

  @category %{id: 1, name: "Test"}
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
    {:ok, game} = Game.new(@category, names, questions(), Keyword.merge(@no_shuffle, opts))
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
      assert {:error, :invalid_player_count} = Game.new(@category, ["Solo"], questions())
      assert {:error, :invalid_player_count} = Game.new(@category, ~w(a b c d e), questions())
      assert {:error, :blank_player_name} = Game.new(@category, ["Ann", "  "], questions())
      assert {:error, :no_questions} = Game.new(@category, ["Ann", "Bob"], [])

      assert {:error, :invalid_mode} =
               Game.new(@category, ["Ann", "Bob"], questions(), mode: "nope")
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

  test "snapshots from before the board modes open as finished" do
    legacy = %{
      "category_id" => 1,
      "category_name" => "Old",
      "players" => [%{"name" => "Ann", "score" => 10}],
      "questions" => [%{"topic" => "A"}],
      "round" => 1,
      "turn_order" => [0],
      "phase" => "answering"
    }

    assert %Game{phase: :finished, players: [%{name: "Ann", score: 10}]} = Game.from_map(legacy)
  end
end
