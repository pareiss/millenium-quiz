defmodule MillenniumQuiz.Games do
  @moduledoc """
  Public API for running games.

  Game state is managed in three layers:

    1. `MillenniumQuiz.Game` - pure rules, no side effects.
    2. `MillenniumQuiz.Games.Server` - one GenServer per running game,
       registered by id in `MillenniumQuiz.Games.Registry`, started on demand
       under `MillenniumQuiz.Games.Supervisor`.
    3. The `games` table - a JSONB snapshot after every change, so games
       survive pauses, restarts and moving to another device.

  Callers (LiveViews) only send intents and receive `{:game_updated, view}`
  messages via PubSub; they never own game state.
  """

  import Ecto.Query, warn: false

  alias MillenniumQuiz.{Game, Quiz, Repo}
  alias MillenniumQuiz.Games.{GameRecord, Server}

  @pubsub MillenniumQuiz.PubSub

  @doc """
  Creates and persists a new game. Returns `{:ok, game_id}`.

  `opts` go to `MillenniumQuiz.Game.new/4`, e.g. `mode: :ascending`.
  """
  def create_game(category_id, player_names, opts \\ []) do
    category = Quiz.get_category!(category_id)
    questions = Quiz.questions_for_category(category.id)

    with {:ok, game} <- Game.new(category, player_names, questions, opts) do
      %GameRecord{category_id: category.id, status: :active, state: Game.to_map(game)}
      |> Repo.insert()
      |> case do
        {:ok, record} -> {:ok, record.id}
        error -> error
      end
    end
  end

  @doc "Returns `{:ok, %{id, status, game}}` or `{:error, :not_found}`."
  def fetch_game(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> call(id, :get)
      :error -> {:error, :not_found}
    end
  end

  def choose(id, question_index), do: call(id, {:choose, question_index})
  def answer(id, choice), do: call(id, {:answer, choice})
  def next_round(id), do: call(id, :next_round)
  def finish(id), do: call(id, :finish)
  def pause(id), do: call(id, :pause)
  def resume(id), do: call(id, :resume)

  @doc "Paused or active games among `ids`, newest first (for the home page)."
  def list_unfinished_games(ids) when is_list(ids) do
    ids = for id <- ids, {:ok, uuid} <- [Ecto.UUID.cast(id)], do: uuid

    Repo.all(
      from g in GameRecord,
        where: g.id in ^ids and g.status in [:active, :paused],
        order_by: [desc: g.updated_at]
    )
    |> Enum.map(&%{id: &1.id, status: &1.status, game: Game.from_map(&1.state)})
  end

  def subscribe(id), do: Phoenix.PubSub.subscribe(@pubsub, topic(id))

  @doc false
  def broadcast(id, view), do: Phoenix.PubSub.broadcast(@pubsub, topic(id), {:game_updated, view})

  defp topic(id), do: "game:#{id}"

  # A paused or idle game has no process; start one from the snapshot.
  # If the process is just stopping (e.g. pausing), retry once.
  defp call(id, message, retries \\ 1) do
    with {:ok, pid} <- ensure_started(id) do
      GenServer.call(pid, message)
    end
  catch
    :exit, _reason when retries > 0 -> call(id, message, retries - 1)
  end

  defp ensure_started(id) do
    case DynamicSupervisor.start_child(MillenniumQuiz.Games.Supervisor, {Server, id}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
