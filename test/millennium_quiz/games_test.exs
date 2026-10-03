defmodule MillenniumQuiz.GamesTest do
  use MillenniumQuiz.DataCase

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
end
