defmodule MillenniumQuiz.GamesTest do
  use MillenniumQuiz.DataCase

  import Ecto.Query
  import MillenniumQuiz.QuizFixtures
  import MillenniumQuiz.BoardGameFixtures, only: [board_format_fixture: 0]

  alias MillenniumQuiz.{Game, Games}
  alias MillenniumQuiz.Quiz.Question
  alias MillenniumQuiz.Games.{GameRecord, Server}

  setup do
    format = playable_format_fixture(1)
    {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])
    %{id: id}
  end

  defp play_question(id, index) do
    {:ok, _} = Games.choose(id, index)
    {:ok, _} = Games.answer(id, 0)
    {:ok, view} = Games.answer(id, 1)
    view
  end

  test "actions are persisted and broadcast", %{id: id} do
    Games.subscribe(id)
    view = play_question(id, 0)

    assert view.game.phase == :revealed
    assert_receive {:game_updated, %{game: %Game{phase: :revealed}}}

    stored = Repo.get!(GameRecord, id)
    assert Game.from_map(stored.state) == view.game
  end

  test "moving a question afterwards does not change a running game's damage" do
    format = playable_format_fixture(2)
    {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])
    {:ok, %{game: game}} = Games.fetch_game(id)
    before = Enum.map(game.questions, &{&1.id, &1.damage})

    # the first question of the first topic moves down: its position, and so
    # its damage for new games, changes
    topic = hd(MillenniumQuiz.Quiz.get_format!(format.id).topics)
    moved = hd(topic.questions)
    assert MillenniumQuiz.Quiz.get_question!(moved.id).position == 0
    MillenniumQuiz.Quiz.move_question(moved, :down)
    assert MillenniumQuiz.Quiz.get_question!(moved.id).position == 1
    assert Question.damage(1) != Question.damage(0)

    {:ok, %{game: after_game}} = Games.fetch_game(id)
    assert Enum.map(after_game.questions, &{&1.id, &1.damage}) == before

    assert Enum.map(Repo.get!(GameRecord, id).state["questions"], &{&1["id"], &1["damage"]}) ==
             before
  end

  test "a game continues from its snapshot after the process is gone", %{id: id} do
    {:ok, _} = Games.choose(id, 1)
    [{pid, _}] = Registry.lookup(MillenniumQuiz.Games.Registry, id)

    ref = Process.monitor(pid)
    DynamicSupervisor.terminate_child(MillenniumQuiz.Games.Supervisor, pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}

    {:ok, view} = Games.fetch_game(id)
    assert %{phase: :answering, current: 1} = view.game
  end

  test "pause stops the process, resume continues", %{id: id} do
    {:ok, _} = Games.fetch_game(id)
    [{pid, _}] = Registry.lookup(MillenniumQuiz.Games.Registry, id)
    ref = Process.monitor(pid)

    assert {:ok, %{status: :paused}} = Games.pause(id)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert Repo.get!(GameRecord, id).status == :paused

    assert {:error, :invalid_status} = Games.choose(id, 0)
    assert {:ok, %{status: :active}} = Games.resume(id)
    assert {:ok, _} = Games.choose(id, 0)
  end

  test "playing to the end marks the game finished", %{id: id} do
    play_question(id, 0)
    {:ok, _} = Games.next_round(id)
    play_question(id, 1)
    assert {:ok, %{status: :finished}} = Games.next_round(id)
    assert Games.list_unfinished_games([id]) == []
  end

  test "the starting life points go to the game; others are refused" do
    format = playable_format_fixture(2)
    assert {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"], start_lp: 8000)
    assert {:ok, %{game: %Game{start_lp: 8000, players: [%{lp: 8000}, _]}}} = Games.fetch_game(id)
    assert {:error, :invalid_start_lp} = Games.create_game(format.id, ["Ann", "Bob"], start_lp: 1)
  end

  describe "a score game saved before the life points" do
    setup do
      state = %{
        "format_name" => "Old",
        "mode" => "free",
        "players" => [%{"name" => "Ann", "score" => 30}, %{"name" => "Bob", "score" => 10}],
        "topics" => ["A"],
        "questions" => [],
        "round" => 1,
        "turn_order" => [0, 1],
        "phase" => "choosing"
      }

      record = Repo.insert!(%GameRecord{status: :active, state: state})
      %{old_id: record.id}
    end

    test "opens as a finished game that cannot be played", %{old_id: id} do
      assert {:ok, %{game: %Game{phase: :finished, start_lp: nil}}} = Games.fetch_game(id)
      assert {:error, :invalid_status} = Games.choose(id, 0)
    end

    test "is finished in the table too, so it is not shown as paused", %{old_id: id} do
      Repo.get!(GameRecord, id) |> Ecto.Changeset.change(status: :paused) |> Repo.update!()
      assert {:ok, %{status: :finished}} = Games.fetch_game(id)
      assert Repo.get!(GameRecord, id).status == :finished
    end

    test "is not offered to continue", %{old_id: id} do
      assert Games.list_unfinished_games([id]) == []
    end
  end

  describe "a question with a board" do
    setup do
      Map.merge(%{codes: MillenniumQuiz.BoardGameFixtures.codes()}, board_format_fixture())
    end

    defp board_question(game, question), do: Enum.find(game.questions, &(&1.id == question.id))

    test "the game snapshots the resolved board and each card once", %{
      format: format,
      question: question,
      codes: codes
    } do
      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])
      {:ok, %{game: game}} = Games.fetch_game(id)
      q = board_question(game, question)

      assert %{"rule" => "mr1_2", "turn" => 3, "players" => [p1, p2]} = q.board

      assert [nil, %{"name" => "Board Card 1001", "pos" => "atk"}, %{"pos" => "set"}, nil, nil] =
               p1["monsters"]

      assert %{"name" => "Board Card 1007"} = p2["field"]
      assert [%{"password" => 1004}] = p1["grave"]

      # 8 cards in the pool, 1004 is on the board twice: one entry each
      in_pool = codes |> Map.delete(:missing) |> Map.values() |> Enum.sort()
      assert game.board_cards |> Map.keys() |> Enum.sort() == Enum.map(in_pool, &to_string/1)

      assert %{
               name: "Board Card 1001",
               text: "Text of card 1001.",
               attribute: "DARK",
               id: card_id
             } =
               game.board_cards["1001"]

      assert is_integer(card_id)

      # the other questions have no board
      others = Enum.reject(game.questions, &(&1.id == question.id))
      assert Enum.all?(others, &(&1.board == nil))

      # the stored state is plain JSON and loads back the same
      stored = Repo.get!(GameRecord, id).state
      assert stored |> Jason.encode!() |> Jason.decode!() |> Game.from_map() == game
    end

    test "editing the question or the cards afterwards does not change the game", %{
      format: format,
      question: question,
      codes: codes
    } do
      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])
      {:ok, %{game: game}} = Games.fetch_game(id)
      stored = Repo.get!(GameRecord, id).state

      question |> Ecto.Changeset.change(board: nil) |> Repo.update!()

      Repo.update_all(from(c in MillenniumQuiz.Cards.Card, where: c.password == ^codes.p1_up),
        set: [name: "Renamed", texts: %{"en" => "New text."}, atk: "9999"]
      )

      # Stop the process so that the game is loaded from the stored JSONB,
      # not read from memory.
      [{pid, _}] = Registry.lookup(MillenniumQuiz.Games.Registry, id)
      ref = Process.monitor(pid)
      DynamicSupervisor.terminate_child(MillenniumQuiz.Games.Supervisor, pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}

      {:ok, %{game: again}} = Games.fetch_game(id)
      assert again == game
      assert Repo.get!(GameRecord, id).state == stored
      assert again.board_cards["1001"].name == "Board Card 1001"
    end

    @tag capture_log: true
    test "a board that does not validate is left out and the game still plays", %{
      format: format,
      question: question,
      codes: codes
    } do
      # a card that is not in the pool
      board = MillenniumQuiz.BoardGameFixtures.stored_board()
      bad = put_in(board, ["players", Access.at(0), "grave"], [%{"code" => codes.missing}])
      question |> Ecto.Changeset.change(board: bad) |> Repo.update!()

      assert {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])
      {:ok, %{game: game}} = Games.fetch_game(id)

      assert board_question(game, question).board == nil
      assert game.board_cards == %{}
      assert {:ok, _} = Games.choose(id, 0)
    end

    @tag capture_log: true
    test "a board that stops fitting after a Master Rule date change is left out", %{
      format: format,
      question: question,
      codes: codes
    } do
      # An overlay unit on an Xyz monster, in a format after Xyz Monsters exist.
      format |> Ecto.Changeset.change(date: ~D[2012-06-01]) |> Repo.update!()

      Repo.update_all(from(c in MillenniumQuiz.Cards.Card, where: c.password == ^codes.p1_up),
        set: [frame_type: "xyz"]
      )

      board = MillenniumQuiz.BoardGameFixtures.stored_board()

      with_overlay =
        put_in(board, ["players", Access.at(0), "monsters", Access.at(1), "overlay"], [
          codes.hand
        ])

      question |> Ecto.Changeset.change(board: with_overlay) |> Repo.update!()

      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])
      {:ok, %{game: game}} = Games.fetch_game(id)
      assert %{"rule" => "mr1_2"} = board_question(game, question).board

      # Xyz Monsters now come out after the format's date
      assert {:ok, _} =
               MillenniumQuiz.Quiz.MasterRules.save(%{
                 "mr3" => "2014-01-01",
                 "mr4" => "2017-04-01",
                 "xyz" => "2013-01-01"
               })

      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])
      {:ok, %{game: game}} = Games.fetch_game(id)
      assert board_question(game, question).board == nil
    end

    test "the board survives the game process being restarted", %{
      format: format,
      question: question
    } do
      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])
      {:ok, _} = Games.choose(id, 0)
      [{pid, _}] = Registry.lookup(MillenniumQuiz.Games.Registry, id)
      ref = Process.monitor(pid)
      DynamicSupervisor.terminate_child(MillenniumQuiz.Games.Supervisor, pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}

      {:ok, %{game: game}} = Games.fetch_game(id)
      assert %{"rule" => "mr1_2"} = board_question(game, question).board
    end
  end

  test "unknown or malformed ids" do
    assert {:error, :not_found} = Games.fetch_game(Ecto.UUID.generate())
    assert {:error, :not_found} = Games.fetch_game("not-a-uuid")
  end

  test "server stops itself when idle", %{id: id} do
    {:ok, _} = Games.fetch_game(id)
    [{pid, _}] = Registry.lookup(MillenniumQuiz.Games.Registry, id)
    ref = Process.monitor(pid)
    send(pid, :timeout)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert Server.via(id) |> GenServer.whereis() |> is_nil()
  end

  test "a game whose row was deleted under a running server ends cleanly", %{id: id} do
    {:ok, _} = Games.fetch_game(id)
    [{pid, _}] = Registry.lookup(MillenniumQuiz.Games.Registry, id)
    ref = Process.monitor(pid)

    # what the expiry job does to a game that was opened just after it was picked
    Repo.delete_all(from g in GameRecord, where: g.id == ^id)

    assert Games.choose(id, 0) == {:error, :not_found}
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert Games.fetch_game(id) == {:error, :not_found}
  end

  describe "delete_expired/1" do
    setup do
      previous =
        for key <- [:game_expiry_days, :game_expiry_finished_days],
            do: {key, Application.fetch_env(:millennium_quiz, key)}

      Application.put_env(:millennium_quiz, :game_expiry_days, 30)
      Application.put_env(:millennium_quiz, :game_expiry_finished_days, 7)

      on_exit(fn ->
        for {key, result} <- previous do
          case result do
            {:ok, value} -> Application.put_env(:millennium_quiz, key, value)
            :error -> Application.delete_env(:millennium_quiz, key)
          end
        end
      end)
    end

    defp backdate(id, status, days) do
      updated_at =
        DateTime.utc_now()
        |> DateTime.add(-days * 86_400 - 60, :second)
        |> DateTime.truncate(:second)

      Repo.update_all(from(g in GameRecord, where: g.id == ^id),
        set: [status: status, updated_at: updated_at]
      )
    end

    defp exists?(id), do: Repo.exists?(from g in GameRecord, where: g.id == ^id)

    test "deletes by age and status and returns the count", %{id: fresh} do
      format = playable_format_fixture(2)
      new = fn -> elem(Games.create_game(format.id, ["Ann", "Bob"]), 1) end

      [old_active, old_paused, old_finished, young_active, young_paused, young_finished] =
        for _ <- 1..6, do: new.()

      backdate(old_active, :active, 31)
      backdate(old_paused, :paused, 31)
      backdate(old_finished, :finished, 8)
      backdate(young_active, :active, 29)
      backdate(young_paused, :paused, 29)
      backdate(young_finished, :finished, 6)

      assert Games.delete_expired() == 3

      for id <- [old_active, old_paused, old_finished], do: refute(exists?(id))
      for id <- [fresh, young_active, young_paused, young_finished], do: assert(exists?(id))
      assert Games.delete_expired() == 0
    end

    test "a finished game that is 10 days old goes, an active one of 10 days stays", %{id: id} do
      other = elem(Games.create_game(playable_format_fixture(3).id, ["Ann", "Bob"]), 1)
      backdate(id, :finished, 10)
      backdate(other, :active, 10)

      assert Games.delete_expired() == 1
      refute exists?(id)
      assert exists?(other)
    end

    test "the limits come from the application environment", %{id: id} do
      Application.put_env(:millennium_quiz, :game_expiry_days, 2)
      backdate(id, :paused, 3)
      assert Games.delete_expired() == 1
      refute exists?(id)
    end

    test "takes the time as an argument", %{id: id} do
      later = DateTime.add(DateTime.utc_now(), 31 * 86_400, :second)
      assert Games.delete_expired(later) == 1
      refute exists?(id)
    end

    test "skips a game that still has a running process", %{id: id} do
      {:ok, _} = Games.fetch_game(id)
      backdate(id, :paused, 40)

      assert Games.delete_expired() == 0
      assert exists?(id)

      [{pid, _}] = Registry.lookup(MillenniumQuiz.Games.Registry, id)
      ref = Process.monitor(pid)
      DynamicSupervisor.terminate_child(MillenniumQuiz.Games.Supervisor, pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}

      assert Games.delete_expired() == 1
      refute exists?(id)
    end
  end

  describe "game limit" do
    setup do
      on_exit(fn -> Application.delete_env(:millennium_quiz, :game_limit) end)
      %{format: playable_format_fixture(1)}
    end

    test "refuses a new game at the cap and inserts nothing", %{format: format} do
      Application.put_env(:millennium_quiz, :game_limit, Repo.aggregate(GameRecord, :count))

      assert Games.create_game(format.id, ["Ann", "Bob"]) == {:error, :full}

      assert Repo.aggregate(GameRecord, :count) ==
               Application.get_env(:millennium_quiz, :game_limit)
    end

    test "allows a game below the cap", %{format: format} do
      Application.put_env(:millennium_quiz, :game_limit, Repo.aggregate(GameRecord, :count) + 1)

      assert {:ok, _id} = Games.create_game(format.id, ["Ann", "Bob"])
      assert {:error, :full} = Games.create_game(format.id, ["Ann", "Bob"])
    end

    test "frees room by deleting expired games first, never young ones", %{format: format, id: id} do
      Application.put_env(:millennium_quiz, :game_limit, Repo.aggregate(GameRecord, :count))
      assert {:error, :full} = Games.create_game(format.id, ["Ann", "Bob"])
      assert Repo.get(GameRecord, id)

      old = DateTime.add(DateTime.utc_now(), -365 * 86_400, :second)
      Repo.update_all(from(g in GameRecord, where: g.id == ^id), set: [updated_at: old])

      assert {:ok, _} = Games.create_game(format.id, ["Ann", "Bob"])
      refute Repo.get(GameRecord, id)
    end
  end
end
