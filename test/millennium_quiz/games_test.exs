defmodule MillenniumQuiz.GamesTest do
  use MillenniumQuiz.DataCase

  import Ecto.Query
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{Game, Games}
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
end
