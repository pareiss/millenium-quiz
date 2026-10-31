defmodule MillenniumQuiz.Games.Server do
  @moduledoc """
  One process per running game.

  The process serializes every action on a game (two quick taps can't both
  count), saves a snapshot to Postgres after each change and broadcasts the
  new state to every LiveView subscribed to `"game:<id>"`.

  It is started on demand by `MillenniumQuiz.Games` and stops when paused or
  after 30 idle minutes. Since the snapshot is
  in the database, a stopped game can always be picked up again, also after a
  deploy or on another node.
  """
  use GenServer, restart: :transient

  alias MillenniumQuiz.{Game, Games, Repo}
  alias MillenniumQuiz.Games.GameRecord

  @idle_timeout :timer.minutes(30)

  def start_link(id) do
    GenServer.start_link(__MODULE__, id, name: via(id))
  end

  def via(id), do: {:via, Registry, {MillenniumQuiz.Games.Registry, id}}

  @impl true
  def init(id) do
    case Repo.get(GameRecord, id) do
      nil ->
        {:stop, :not_found}

      record ->
        game = record.state |> Game.from_map() |> Games.heal_avatars()
        {:ok, %{record: finish_record(record, game), game: game}, @idle_timeout}
    end
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, {:ok, view(state)}, state, @idle_timeout}
  end

  def handle_call({:choose, index}, _from, state) do
    update(state, &Game.choose(&1, index))
  end

  def handle_call({:answer, choice}, _from, state) do
    update(state, &Game.answer(&1, choice))
  end

  def handle_call(:next_round, _from, state) do
    update(state, &Game.next_round/1)
  end

  def handle_call(:finish, _from, state) do
    update(state, &Game.finish/1)
  end

  def handle_call(:pause, _from, %{record: %{status: :active}} = state) do
    case save(state, state.game, :paused) do
      {:ok, state} -> {:stop, :normal, {:ok, view(state)}, state}
      :gone -> gone(state)
    end
  end

  def handle_call(:resume, _from, %{record: %{status: :paused}} = state) do
    case save(state, state.game, :active) do
      {:ok, state} -> {:reply, {:ok, view(state)}, state, @idle_timeout}
      :gone -> gone(state)
    end
  end

  def handle_call(action, _from, state) when action in [:pause, :resume] do
    {:reply, {:error, :invalid_status}, state, @idle_timeout}
  end

  @impl true
  def handle_info(:timeout, state), do: {:stop, :normal, state}

  defp update(%{record: %{status: :active}} = state, fun) do
    case fun.(state.game) do
      {:ok, game} ->
        status = if game.phase == :finished, do: :finished, else: :active

        case save(state, game, status) do
          {:ok, state} -> {:reply, {:ok, view(state)}, state, @idle_timeout}
          :gone -> gone(state)
        end

      {:error, _} = error ->
        {:reply, error, state, @idle_timeout}
    end
  end

  defp update(state, _fun), do: {:reply, {:error, :invalid_status}, state, @idle_timeout}

  # `:gone` when the row was deleted under us (the expiry job removed a game
  # that was opened just after it had been picked): the game is over.
  defp save(state, game, status) do
    record =
      state.record
      |> Ecto.Changeset.change(state: Game.to_map(game), status: status)
      |> Repo.update!()

    state = %{state | record: record, game: game}
    Games.broadcast(record.id, view(state))
    {:ok, state}
  rescue
    Ecto.StaleEntryError -> :gone
  end

  # A game that loads as finished (an old score game, which `Game.from_map`
  # always opens as finished) must also be finished in the table, or it would
  # show the pause screen, stay remembered on the device and expire late.
  defp finish_record(%{status: status} = record, %{phase: :finished}) when status != :finished do
    record |> Ecto.Changeset.change(status: :finished) |> Repo.update!()
  rescue
    Ecto.StaleEntryError -> record
  end

  defp finish_record(record, _game), do: record

  defp gone(state), do: {:stop, :normal, {:error, :not_found}, state}

  defp view(%{record: record, game: game}),
    do: %{id: record.id, status: record.status, game: game}
end
