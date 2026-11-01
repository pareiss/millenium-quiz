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

  require Logger

  alias MillenniumQuiz.{Avatars, Cards.Card, Game, Quiz, Repo}
  alias MillenniumQuiz.Quiz.Board
  alias MillenniumQuiz.Games.{GameRecord, Server}

  @pubsub MillenniumQuiz.PubSub

  @doc """
  Creates and persists a new game. Returns `{:ok, game_id}`.

  `opts` go to `MillenniumQuiz.Game.new/4`, e.g. `mode: :ascending`.
  """
  def create_game(format_id, player_names, opts \\ []) do
    format = Quiz.get_format!(format_id)
    questions = Quiz.questions_for_format(format.id)

    opts = Keyword.put_new(opts, :boards, board_snapshots(questions, format.date))

    with {:ok, game} <- Game.new(format, player_names, questions, opts),
         :ok <- ensure_room() do
      insert_record(format, game)
    end
  rescue
    # A full or unreachable database must not crash the caller (an unknown
    # format still raises: that is a bad link, not a database problem).
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.error("Could not save a new game: #{Exception.message(error)}")
      {:error, :insert_failed}
  end

  # The boards of the questions, resolved on the format's date, with the cards on
  # them loaded once for all boards (`Game.new/4`, option `:boards`). The game
  # keeps this copy: a later edit of a question or of a card changes nothing.
  # A board that does not pass `Board.validate/2` on that date (a card that is
  # not in the pool, a card released later, a zone the rule lacks) is left out:
  # the question is played without a board and shows no Board button.
  defp board_snapshots(questions, date) do
    resolved =
      for %{board: %{} = stored} = q <- questions,
          Board.validate(stored, date) == :ok,
          into: %{} do
        {q.id, Board.resolve(stored, date)}
      end

    passwords =
      resolved |> Map.values() |> Enum.flat_map(&displayed_passwords/1) |> Enum.uniq()

    cards =
      if passwords == [],
        do: %{},
        else:
          Repo.all(from c in Card, where: c.password in ^passwords, preload: :card_texts)
          |> Map.new(&{&1.password, &1})

    Map.new(resolved, fn {id, board} ->
      shown = for p <- displayed_passwords(board), card = cards[p], do: card
      {id, %{board: board, cards: shown}}
    end)
  end

  # The passwords of the cards a resolved board draws (overlay units are only a
  # count, and the Extra Monster Zones only exist under Master Rule 4), once each.
  defp displayed_passwords(board) do
    zones =
      for player <- board["players"],
          zone <- ~w(monsters spells hand grave banished extra),
          card <- player[zone],
          do: card

    fields = for player <- board["players"], do: player["field"]

    emz = if board["rule"] == "mr4", do: board["emz"], else: []

    (zones ++ fields ++ emz)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1["password"])
    |> Enum.uniq()
  end

  defp insert_record(format, game) do
    %GameRecord{format_id: format.id, status: :active, state: Game.to_map(game)}
    |> Repo.insert()
    |> case do
      {:ok, record} -> {:ok, record.id}
      {:error, _changeset} -> {:error, :insert_failed}
    end
  end

  # `:game_limit` (nil = unlimited) caps the number of rows in `games`, for
  # hosts with a row quota. Expired games are cleaned up first (this never
  # touches young rows), then the rows are counted.
  defp ensure_room do
    case Application.get_env(:millennium_quiz, :game_limit) do
      limit when is_integer(limit) and limit > 0 ->
        cond do
          Repo.aggregate(GameRecord, :count) < limit ->
            :ok

          true ->
            delete_expired()
            if Repo.aggregate(GameRecord, :count) < limit, do: :ok, else: {:error, :full}
        end

      _ ->
        :ok
    end
  end

  @default_expiry_days 30
  @default_expiry_finished_days 7

  @doc """
  Deletes games nobody touched for too long and returns how many.

  Active and paused games expire after `:game_expiry_days` (default 30), finished
  ones after `:game_expiry_finished_days` (default 7), measured on `updated_at`.
  A game that still has a running `Games.Server` is skipped (a server stops after
  30 idle minutes, so it is simply caught by the next run); stopping it would
  race with a player who just opened the link. The delete re-checks the age, so a
  game saved in the meantime survives.
  """
  def delete_expired(now \\ DateTime.utc_now()) do
    active_days = expiry_days(:game_expiry_days, @default_expiry_days)
    finished_days = expiry_days(:game_expiry_finished_days, @default_expiry_finished_days)
    active_cutoff = DateTime.add(now, -active_days * 86_400, :second)
    finished_cutoff = DateTime.add(now, -finished_days * 86_400, :second)

    expired =
      dynamic(
        [g],
        (g.status == :finished and g.updated_at < ^finished_cutoff) or
          (g.status != :finished and g.updated_at < ^active_cutoff)
      )

    ids =
      from(g in GameRecord, where: ^expired, select: g.id)
      |> Repo.all()
      |> Enum.reject(&running?/1)

    {count, _} =
      Repo.delete_all(from g in GameRecord, where: ^dynamic([g], g.id in ^ids and ^expired))

    count
  end

  defp running?(id), do: Registry.lookup(MillenniumQuiz.Games.Registry, id) != []

  defp expiry_days(key, default) do
    case Application.get_env(:millennium_quiz, key, default) do
      days when is_integer(days) and days > 0 -> days
      _ -> default
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

  @doc "Paused or active games among `ids`, newest first (for the home page, which shows
  no pictures, so they are not healed here; `Games.Server` heals when a game opens)."
  def list_unfinished_games(ids) when is_list(ids) do
    ids = for id <- ids, {:ok, uuid} <- [Ecto.UUID.cast(id)], do: uuid

    Repo.all(
      from g in GameRecord,
        where: g.id in ^ids and g.status in [:active, :paused],
        order_by: [desc: g.updated_at]
    )
    |> Enum.map(&%{id: &1.id, status: &1.status, game: Game.from_map(&1.state)})
    # Score games from before the life points open as finished: nothing to continue.
    |> Enum.reject(&(&1.game.phase == :finished))
  end

  @doc """
  A player whose picture is a card that has since left the card pool gets a
  picture of the default pool instead (a different one for each such player,
  starting from a place that depends on the card, so the same game always
  shows the same replacement). Everything else stays as it is.
  """
  def heal_avatars(%Game{players: players} = game) do
    ids = for %{avatar: slug} <- players, id = Avatars.card_id(slug), do: id

    existing =
      if ids == [],
        do: MapSet.new(),
        else: MapSet.new(Repo.all(from c in Card, where: c.id in ^ids, select: c.id))

    if Enum.all?(ids, &(&1 in existing)) do
      game
    else
      taken = for %{avatar: slug} <- players, do: slug
      {players, _taken} = Enum.map_reduce(players, taken, &heal_player(&1, &2, existing))
      %{game | players: players}
    end
  end

  defp heal_player(%{avatar: slug} = player, taken, existing) do
    case Avatars.card_id(slug) do
      id when is_integer(id) ->
        if id in existing do
          {player, taken}
        else
          default = Avatars.default_slugs()
          offset = rem(id, length(default))
          {front, back} = Enum.split(default, offset)
          free = Enum.find(back ++ front, hd(default), &(&1 not in taken))
          {%{player | avatar: free}, [free | taken]}
        end

      nil ->
        {player, taken}
    end
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
