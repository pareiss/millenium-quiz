defmodule MillenniumQuiz.Game do
  @moduledoc """
  Pure functional core of a hot-seat trivia game.

  No processes, no database: every function takes a `%Game{}` and returns a
  new one (or an error). That keeps the rules easy to test and to extend
  (timers, jokers, teams, other question kinds...). Process handling and
  persistence live in `MillenniumQuiz.Games`.

  ## Board and modes

  The topics of the format are the columns of a board, and every question
  is a cell that only shows its points. Players take turns choosing; then
  every player answers the chosen question, starting with the chooser.
  Picks stay hidden until the reveal.

  ## Life points

  Every player starts with `start_lp` life points (4000 or 8000). At the reveal
  everyone who was wrong loses the question's `damage` (see `Question.damage/1`,
  copied when the game is created), never going below 0; right answers change
  nothing. A player on 0 is eliminated (`eliminated_at` is the round) and is
  skipped from then on. The game ends when at most one player is left or the
  board is empty, or early with `finish/1`. If the last players all drop to 0
  in the same round the game is a draw between them (`draw?/1`).

  Games saved before the life points were score games. They load as finished
  and read-only (`start_lp` is nil, players have a `score`, questions `points`).

    * `:free` ("Heart of the Cards") - any unanswered question can be chosen.
    * `:ascending` ("Level Up!") - the player chooses a topic and gets its
      easiest unanswered question.

  ## Flow

      :choosing --(choose)--> :answering --(last answer)--> :revealed
          ^                                               |
          +------------------(next_round)-----------------+
                                                          |
                              (board empty / finish) --> :finished

  Questions are snapshotted when the game is created, so admins can edit
  content while games are running without breaking them.

  ## The board of a question

  A question may have a read-only Yu-Gi-Oh! board (`Quiz.Board`). Both parts
  of the snapshot are plain JSON data:

    * `board` in the question - the resolved board (`Quiz.Board.resolve/3`:
      string keys, cards with name, kind, ATK/DEF, level, artwork url,
      position), or nil. It names each card by `"password"`.
    * `board_cards` in the game - the full card (`t:card/0`, the same maps as
      the `cards` of a question, so `CardComponents.card/1` draws them) of
      every card on any board, keyed by its password as a string
      (`"46986414"`). A card is stored once per game, however many boards and
      zones show it: the boards of a puzzle pack share most of their cards and
      each card with its text is ~0.7 KB, the board itself ~0.2 KB per card
      shown. A card that is not in the pool has no entry. Without boards it
      is `%{}`.

  The resolving needs the database, so `Game.new/4` does not do it: the caller
  passes the result in the `:boards` option (see there). Snapshots from before
  boards load with `board: nil` in every question and `board_cards: %{}`.
  """

  alias MillenniumQuiz.Cards
  alias MillenniumQuiz.Quiz.Question

  @min_players 2
  @max_players 4
  # The new-game form limits names to the same length.
  @max_name_length 24
  @modes [:free, :ascending]
  @start_lps [4000, 8000]
  @default_start_lp 4000

  # What is printed on a card besides its name and text, copied as stored.
  @card_details [
    :kind,
    :property,
    :frame_type,
    :monster_type_line,
    :attribute,
    :level,
    :rank,
    :link_arrows,
    :atk,
    :def,
    :pendulum_scale
  ]

  defstruct format_id: nil,
            format_name: nil,
            format_date: nil,
            mode: :free,
            start_lp: nil,
            players: [],
            topics: [],
            questions: [],
            round: 1,
            turn_order: [],
            turn_index: 0,
            current: nil,
            picks: [],
            answered: 0,
            phase: :choosing,
            board_cards: %{}

  @type mode :: :free | :ascending
  @typedoc """
  `eliminated_at` is the round the player dropped to 0 (nil while alive).
  `lp` is nil in games from before the life points, which only have a `score`
  (nil in all other games).
  """
  @type player :: %{
          name: String.t(),
          lp: non_neg_integer() | nil,
          eliminated_at: pos_integer() | nil,
          score: non_neg_integer() | nil,
          avatar: String.t() | nil
        }
  @type result :: %{chooser: non_neg_integer(), picks: [non_neg_integer()]}
  @type question :: %{
          id: integer(),
          topic: String.t(),
          column: non_neg_integer(),
          text: String.t(),
          damage: pos_integer() | nil,
          points: pos_integer() | nil,
          choices: [String.t()],
          correct: non_neg_integer(),
          cards: [card()],
          board: map() | nil,
          result: result() | nil
        }
  @typedoc """
  A card as printed on the format's date. `id` is the card pool id (for the
  artwork); it and the printed details are nil in snapshots taken before
  they were stored. `owner` is the player the card belongs to in the question
  (1 or 2), nil for nobody and in snapshots taken before owners existed.
  """
  @type card :: %{
          id: integer() | nil,
          name: String.t(),
          text: String.t(),
          set: String.t() | nil,
          kind: String.t() | nil,
          property: String.t() | nil,
          frame_type: String.t() | nil,
          monster_type_line: String.t() | nil,
          attribute: String.t() | nil,
          level: integer() | nil,
          rank: integer() | nil,
          link_arrows: [String.t()],
          atk: String.t() | nil,
          def: String.t() | nil,
          pendulum_scale: integer() | nil,
          pendulum_text: String.t() | nil,
          owner: 1 | 2 | nil
        }
  @type t :: %__MODULE__{
          format_id: integer() | nil,
          format_name: String.t() | nil,
          format_date: Date.t() | nil,
          mode: mode(),
          start_lp: 4000 | 8000 | nil,
          players: [player()],
          topics: [String.t()],
          questions: [question()],
          round: pos_integer(),
          turn_order: [non_neg_integer()],
          turn_index: non_neg_integer(),
          current: non_neg_integer() | nil,
          picks: [non_neg_integer() | nil],
          answered: non_neg_integer(),
          phase: :choosing | :answering | :revealed | :finished,
          board_cards: %{String.t() => card()}
        }

  def min_players, do: @min_players
  def max_players, do: @max_players
  def max_name_length, do: @max_name_length
  def modes, do: @modes
  def start_lps, do: @start_lps
  def default_start_lp, do: @default_start_lp

  def mode_name(:free), do: "Heart of the Cards"
  def mode_name(:ascending), do: "Level Up!"

  def mode_description(:free),
    do: "Trust the heart of the cards: pick any question on the board."

  def mode_description(:ascending),
    do: "Pick a topic and climb its levels: you always get its easiest open question."

  @doc "Parses a mode from a form or JSON value."
  def parse_mode(mode) when mode in @modes, do: {:ok, mode}

  def parse_mode(mode) when is_binary(mode),
    do: parse_mode(Enum.find(@modes, &(to_string(&1) == mode)))

  def parse_mode(_), do: {:error, :invalid_mode}

  @doc "Parses the starting life points from a form or JSON value."
  def parse_start_lp(lp) when lp in @start_lps, do: {:ok, lp}

  def parse_start_lp(lp) when is_binary(lp),
    do: parse_start_lp(Enum.find(@start_lps, &(Integer.to_string(&1) == lp)))

  def parse_start_lp(_), do: {:error, :invalid_start_lp}

  @doc """
  Creates a game from a format, player names and `Question` structs
  (with `:topic` preloaded).

  Options:
    * `:mode` - `:free` (default) or `:ascending`.
    * `:start_lp` - the life points everyone starts with: 4000 (default) or
      8000, else `{:error, :invalid_start_lp}`.
    * `:shuffle` - function used for every random decision, defaults to
      `Enum.shuffle/1`. Tests pass `& &1` to make games deterministic.
    * `:avatars` - one picture slug per player, or nil for a random one
      (missing entries count as nil). Each must be in the format's pool
      (`Avatars.pool/1`: its avatar cards if `avatar_cards` is loaded and has at
      least `Avatars.min_cards/0` cards, else the set of its date) or the game is refused with
      `{:error, :invalid_avatar}`; two players can't have the same one
      (`{:error, :duplicate_avatars}`). The others get different random ones.
    * `:boards` - `%{question_id => %{board: resolved_board, cards: [%Card{}]}}`
      for the questions that have a board (`Games.create_game/3` builds it).
      The board is copied as given; the cards (with `card_texts` loaded) are
      snapshotted like the cards of a question, as on the format's date, and
      keyed by password into `board_cards` of the game. A question that is not
      in the map has no board.
  """
  def new(format, player_names, questions, opts \\ []) do
    shuffle = Keyword.get(opts, :shuffle, &Enum.shuffle/1)
    names = Enum.map(player_names, &String.trim/1)
    mode = parse_mode(Keyword.get(opts, :mode, :free))
    start_lp = parse_start_lp(Keyword.get(opts, :start_lp, @default_start_lp))
    pool = MillenniumQuiz.Avatars.pool(format)
    chosen = chosen_avatars(Keyword.get(opts, :avatars), pool, length(names))

    cond do
      mode == {:error, :invalid_mode} ->
        mode

      start_lp == {:error, :invalid_start_lp} ->
        start_lp

      length(names) not in @min_players..@max_players ->
        {:error, :invalid_player_count}

      Enum.any?(names, &(&1 == "")) ->
        {:error, :blank_player_name}

      Enum.any?(names, &(String.length(&1) > @max_name_length)) ->
        {:error, :player_name_too_long}

      questions == [] ->
        {:error, :no_questions}

      match?({:error, _}, chosen) ->
        chosen

      true ->
        {:ok, chosen} = chosen
        {:ok, mode} = mode
        {:ok, start_lp} = start_lp
        boards = Keyword.get(opts, :boards, %{})
        {topics, questions} = build_board(questions, format.date, boards)

        {:ok,
         %__MODULE__{
           format_id: format.id,
           format_name: format.name,
           format_date: format.date,
           mode: mode,
           start_lp: start_lp,
           players:
             names
             |> Enum.zip(MillenniumQuiz.Avatars.assign(length(names), shuffle, pool, chosen))
             |> Enum.map(fn {name, avatar} ->
               %{name: name, lp: start_lp, eliminated_at: nil, score: nil, avatar: avatar}
             end),
           topics: topics,
           questions: questions,
           board_cards: snapshot_board_cards(boards, questions, format.date),
           picks: List.duplicate(nil, length(names)),
           turn_order: shuffle.(Enum.to_list(0..(length(names) - 1)))
         }}
    end
  end

  # The picked slugs ("" is nobody's choice, as an unselected form field), padded
  # to one per player.
  defp chosen_avatars(nil, _pool, _count), do: {:ok, []}

  defp chosen_avatars(avatars, pool, count) when is_list(avatars) do
    chosen = Enum.map(avatars, &if(&1 == "", do: nil, else: &1))
    picked = Enum.reject(chosen, &is_nil/1)

    cond do
      length(chosen) > count -> {:error, :invalid_avatar}
      Enum.any?(picked, &(&1 not in pool)) -> {:error, :invalid_avatar}
      length(Enum.uniq(picked)) != length(picked) -> {:error, :duplicate_avatars}
      true -> {:ok, chosen}
    end
  end

  defp chosen_avatars(_other, _pool, _count), do: {:error, :invalid_avatar}

  # Columns in topic order, each column from easiest to hardest.
  defp build_board(questions, date, boards) do
    columns =
      questions
      |> Enum.group_by(& &1.topic_id)
      |> Enum.sort_by(fn {topic_id, [q | _]} -> {q.topic.position, topic_id} end)
      |> Enum.with_index()

    topics = Enum.map(columns, fn {{_, [q | _]}, _} -> q.topic.name end)

    questions =
      Enum.flat_map(columns, fn {{_, column}, index} ->
        column
        |> Enum.sort_by(&{&1.position, &1.id})
        |> Enum.map(&snapshot_question(&1, index, date, Map.get(boards, &1.id)))
      end)

    {topics, questions}
  end

  defp snapshot_question(%Question{} = q, column, date, board) do
    %{
      id: q.id,
      topic: q.topic.name,
      column: column,
      text: q.text,
      submitted_by: q.submitted_by,
      damage: Question.damage(q.position),
      points: nil,
      choices: Enum.map(q.choices, & &1.text),
      correct: Enum.find_index(q.choices, & &1.correct),
      cards: snapshot_cards(q.question_cards, date),
      board: board && board.board,
      result: nil
    }
  end

  defp snapshot_board_cards(boards, questions, date) do
    ids = MapSet.new(questions, & &1.id)

    for {id, %{cards: cards}} <- boards, id in ids, card <- cards, into: %{} do
      {Integer.to_string(card.password), snapshot_card(card, date)}
    end
  end

  # Cards as they read on the format's date (English for now).
  defp snapshot_cards(%Ecto.Association.NotLoaded{}, _date), do: []

  defp snapshot_cards(question_cards, date) do
    for %{card: card} = question_card <- question_cards,
        do: snapshot_card(card, date, question_card.owner)
  end

  @doc """
  A card as the game keeps it: the printed details, the text as it read on
  `date` (English for now) and the owner (1, 2 or nil). `card` needs its
  `card_texts` loaded.
  """
  @spec snapshot_card(struct(), Date.t(), 1 | 2 | nil) :: card()
  def snapshot_card(card, date, owner \\ nil) do
    card
    |> Map.take(@card_details)
    |> Map.merge(Cards.printed_on(card, date))
    |> Map.merge(%{id: card.id, name: card.name, owner: owner})
  end

  ## Queries

  def total_rounds(%__MODULE__{questions: questions}), do: length(questions)

  def current_question(%__MODULE__{current: nil}), do: nil

  def current_question(%__MODULE__{questions: questions, current: index}),
    do: Enum.at(questions, index)

  @doc "Index of the player who chooses this round, nil when the game is over."
  def chooser_index(%__MODULE__{phase: :finished}), do: nil
  def chooser_index(%__MODULE__{} = game), do: Enum.at(game.turn_order, game.turn_index)

  @doc """
  Index of the player who acts now: the chooser, or while answering the
  next player to pick (in turn order, starting with the chooser).
  """
  def current_player_index(%__MODULE__{phase: :answering} = game),
    do: Enum.at(answer_order(game), game.answered)

  def current_player_index(%__MODULE__{} = game), do: chooser_index(game)

  @doc """
  The players in the order they answer this round, chooser first. Players
  who were eliminated in an earlier round are left out; those who dropped to 0
  in this round are still there (until the next round starts).
  """
  def answer_order(%__MODULE__{turn_order: order, turn_index: index} = game) do
    (Enum.drop(order, index) ++ Enum.take(order, index))
    |> Enum.filter(&playing?(game, &1))
  end

  # Whether player `index` took part in the current round.
  defp playing?(game, index) do
    case Enum.at(game.players, index) do
      %{eliminated_at: nil} -> true
      %{eliminated_at: round} -> round == game.round
    end
  end

  @doc "Whether player `index` is still in the game (has life points left)."
  def alive?(%__MODULE__{} = game, index) do
    case Enum.at(game.players, index) do
      %{eliminated_at: nil} -> true
      _ -> false
    end
  end

  defp alive_count(%__MODULE__{players: players}),
    do: Enum.count(players, &is_nil(&1.eliminated_at))

  def current_player(%__MODULE__{} = game) do
    case current_player_index(game) do
      nil -> nil
      index -> Enum.at(game.players, index)
    end
  end

  @doc "The board: one `{topic, [{question_index, question}]}` per column."
  def board(%__MODULE__{} = game) do
    columns =
      game.questions
      |> Enum.with_index()
      |> Enum.group_by(fn {q, _} -> q.column end, fn {q, index} -> {index, q} end)

    game.topics
    |> Enum.with_index()
    |> Enum.map(fn {topic, column} -> {topic, Map.get(columns, column, [])} end)
  end

  @doc "Index of the easiest unanswered question in a column, or nil."
  def next_in_column(%__MODULE__{} = game, column) do
    game.questions
    |> Enum.with_index()
    |> Enum.find_value(fn {q, index} -> q.column == column and is_nil(q.result) && index end)
  end

  @doc "The damage of the easiest open question in a column (\"NEXT ATK\"), or nil."
  def next_damage(%__MODULE__{} = game, column) do
    case next_in_column(game, column) do
      nil -> nil
      index -> Enum.at(game.questions, index).damage
    end
  end

  @doc "Whether the current player may choose question `index` right now."
  def choosable?(%__MODULE__{phase: :choosing} = game, index) do
    case Enum.at(game.questions, index) do
      %{result: nil} = q ->
        game.mode == :free or next_in_column(game, q.column) == index

      _ ->
        false
    end
  end

  def choosable?(%__MODULE__{}, _index), do: false

  @doc "Whether player `index` answered the revealed current question correctly."
  def correct?(%__MODULE__{} = game, index) do
    case current_question(game) do
      %{result: %{picks: picks}, correct: correct} -> Enum.at(picks, index) == correct
      _ -> false
    end
  end

  @doc """
  The life points player `index` had before the revealed current question hit
  them: the start LP minus the damage of every other revealed question they
  got wrong. Exact, because a player who reaches 0 stops answering, so no
  earlier hit was cut off at 0.
  """
  def lp_before_reveal(%__MODULE__{} = game, index) do
    lost =
      for {q, i} <- Enum.with_index(game.questions),
          i != game.current,
          %{result: %{picks: picks}} <- [q],
          pick = Enum.at(picks, index),
          pick != q.correct,
          reduce: 0,
          do: (acc -> acc + q.damage)

    game.start_lp - lost
  end

  @doc "How many players answered an answered question correctly."
  def correct_count(%{result: %{picks: picks}, correct: correct}),
    do: Enum.count(picks, &(&1 == correct))

  @doc "How many players answered a revealed question (eliminated players do not)."
  def answered_count(%{result: %{picks: picks}}), do: Enum.count(picks, &(&1 != nil))

  @doc """
  The ranking, best first, with each player's index: survivors by life points
  (highest first), then the eliminated, the latest eliminated first. Ties keep
  the seating order; `places/1` tells who shares a place. Games from before the
  life points rank by their score.
  """
  def standings(%__MODULE__{} = game) do
    game.players
    |> Enum.with_index()
    |> Enum.sort_by(fn {player, index} -> {rank_key(game, player), index} end)
  end

  # Lower sorts first. Equal keys share a place.
  defp rank_key(%{start_lp: nil}, player), do: {0, -(player.score || 0)}
  defp rank_key(_game, %{eliminated_at: nil} = player), do: {0, -player.lp}
  defp rank_key(_game, player), do: {1, -player.eliminated_at}

  @doc """
  `{player, index, place}` in ranking order. Players with the same life points
  (or eliminated in the same round) share a place; the next one skips ahead
  (1, 1, 3).
  """
  def places(%__MODULE__{} = game) do
    game
    |> standings()
    |> Enum.with_index(1)
    |> Enum.map_reduce(nil, fn {{player, index}, position}, previous ->
      key = rank_key(game, player)

      place =
        case previous do
          {^key, place} -> place
          _ -> position
        end

      {{player, index, place}, {key, place}}
    end)
    |> elem(0)
  end

  @doc "The players on first place, `{player, index}`: several on a tie or draw."
  def winners(%__MODULE__{} = game),
    do: for({player, index, 1} <- places(game), do: {player, index})

  @doc """
  Whether the game ended in a draw: the last players all dropped to 0 in the same
  round (shared first place). A tie on life points is no draw.
  """
  def draw?(%__MODULE__{phase: :finished, start_lp: lp} = game) when not is_nil(lp),
    do: alive_count(game) == 0 and length(winners(game)) > 1

  def draw?(%__MODULE__{}), do: false

  ## Transitions

  @doc "The current player chooses question `index` (see `choosable?/2`)."
  def choose(%__MODULE__{phase: :choosing} = game, index) when is_integer(index) do
    if choosable?(game, index),
      do: {:ok, %{game | current: index, phase: :answering}},
      else: {:error, :invalid_question}
  end

  def choose(%__MODULE__{}, _index), do: {:error, :not_choosing}

  @doc "The current player picks `choice`. Reveals and scores after the last player."
  def answer(%__MODULE__{phase: :answering} = game, choice) when is_integer(choice) do
    question = current_question(game)

    if choice in 0..(length(question.choices) - 1)//1 do
      game
      |> Map.update!(:picks, &List.replace_at(&1, current_player_index(game), choice))
      |> Map.update!(:answered, &(&1 + 1))
      |> maybe_reveal()
      |> then(&{:ok, &1})
    else
      {:error, :invalid_choice}
    end
  end

  def answer(%__MODULE__{}, _choice), do: {:error, :not_answering}

  defp maybe_reveal(%__MODULE__{} = game) do
    if game.answered < length(answer_order(game)) do
      game
    else
      question = current_question(game)

      players =
        game.players
        |> Enum.zip(game.picks)
        |> Enum.with_index()
        |> Enum.map(fn {{player, pick}, index} ->
          if playing?(game, index) and pick != question.correct,
            do: hurt(player, question.damage, game.round),
            else: player
        end)

      result = %{chooser: chooser_index(game), picks: game.picks}

      %{
        game
        | players: players,
          questions: List.replace_at(game.questions, game.current, %{question | result: result}),
          phase: :revealed
      }
    end
  end

  # Life points never drop below 0; the player on 0 is out.
  defp hurt(player, damage, round) do
    lp = max(player.lp - damage, 0)
    %{player | lp: lp, eliminated_at: if(lp == 0, do: round)}
  end

  @doc "Whether the game ends after this reveal: the board is empty or at most one player is left."
  def over?(%__MODULE__{} = game),
    do: Enum.all?(game.questions, & &1.result) or alive_count(game) <= 1

  @doc """
  Passes the turn to the next player who is alive, or finishes when the board is
  empty or at most one player is left.
  """
  def next_round(%__MODULE__{phase: :revealed} = game) do
    if over?(game) do
      {:ok, %{game | phase: :finished}}
    else
      {:ok,
       %{
         game
         | round: game.round + 1,
           phase: :choosing,
           current: nil,
           picks: List.duplicate(nil, length(game.players)),
           answered: 0,
           turn_index: next_turn_index(game, game.turn_index)
       }}
    end
  end

  def next_round(%__MODULE__{}), do: {:error, :not_revealed}

  # Someone is alive (checked by the caller), so this ends.
  defp next_turn_index(game, index) do
    next = rem(index + 1, length(game.turn_order))

    if alive?(game, Enum.at(game.turn_order, next)),
      do: next,
      else: next_turn_index(game, next)
  end

  @doc "Ends the game early. A question that is not revealed yet is not scored."
  def finish(%__MODULE__{} = game), do: {:ok, %{game | phase: :finished}}

  ## Serialization (stored as JSONB in `games.state`)

  def to_map(%__MODULE__{} = game) do
    game
    |> Map.from_struct()
    |> Map.update!(:phase, &Atom.to_string/1)
    |> Map.update!(:mode, &Atom.to_string/1)
  end

  # Snapshots from before the board modes have no "mode"; they open as finished,
  # and so do the score games from before the life points (no "start_lp").
  def from_map(%{"mode" => _} = map) do
    {:ok, mode} = parse_mode(map["mode"])
    no_picks = List.duplicate(nil, length(map["players"]))
    start_lp = map["start_lp"]

    %__MODULE__{
      format_id: map["format_id"] || map["category_id"],
      format_name: map["format_name"] || map["category_name"],
      format_date: date_from_map(map["format_date"]),
      mode: mode,
      start_lp: start_lp,
      players: players_from_map(map["players"]),
      topics: map["topics"],
      questions:
        Enum.map(map["questions"], fn q ->
          %{
            id: q["id"],
            topic: q["topic"],
            column: q["column"],
            text: q["text"],
            submitted_by: q["submitted_by"],
            damage: q["damage"],
            points: q["points"],
            choices: q["choices"],
            correct: q["correct"],
            cards: Enum.map(q["cards"] || [], &card_from_map/1),
            board: q["board"],
            result: q["result"] && result_from_map(q["result"], no_picks)
          }
        end),
      round: map["round"],
      turn_order: map["turn_order"],
      turn_index: map["turn_index"],
      current: map["current"],
      picks: map["picks"] || no_picks,
      answered: map["answered"] || 0,
      board_cards: Map.new(map["board_cards"] || %{}, fn {k, v} -> {k, card_from_map(v)} end),
      phase: if(start_lp, do: phase_from_string(map["phase"]), else: :finished)
    }
  end

  def from_map(%{} = map) do
    %__MODULE__{
      format_id: map["format_id"] || map["category_id"],
      format_name: map["format_name"] || map["category_name"],
      format_date: date_from_map(map["format_date"]),
      mode: :ascending,
      players: players_from_map(map["players"]),
      topics: map["questions"] |> Enum.map(& &1["topic"]) |> Enum.uniq(),
      round: map["round"],
      turn_order: map["turn_order"],
      phase: :finished
    }
  end

  # Older snapshots only have name, text and set, and none has an owner (the
  # player the card belongs to: nil, 1 or 2).
  defp card_from_map(card) do
    details = Map.new(@card_details, &{&1, card[Atom.to_string(&1)]})

    Map.merge(details, %{
      id: card["id"],
      name: card["name"],
      text: card["text"],
      set: card["set"],
      link_arrows: card["link_arrows"] || [],
      pendulum_text: card["pendulum_text"],
      owner: if(card["owner"] in [1, 2], do: card["owner"])
    })
  end

  defp result_from_map(%{"picks" => picks} = result, _no_picks),
    do: %{chooser: result["chooser"], picks: picks}

  # Early board games, where only the chooser answered.
  defp result_from_map(%{"player" => player, "pick" => pick}, no_picks),
    do: %{chooser: player, picks: List.replace_at(no_picks, player, pick)}

  # Snapshots from before categories became formats have `category_*` keys
  # and no date.
  defp date_from_map(nil), do: nil
  defp date_from_map(date), do: Date.from_iso8601!(date)

  # Games saved before the avatars have none; score games have no life points.
  defp players_from_map(players) do
    Enum.map(players, fn player ->
      %{
        name: player["name"],
        lp: player["lp"],
        eliminated_at: player["eliminated_at"],
        score: player["score"],
        avatar: player["avatar"]
      }
    end)
  end

  defp phase_from_string("choosing"), do: :choosing
  defp phase_from_string("answering"), do: :answering
  defp phase_from_string("revealed"), do: :revealed
  defp phase_from_string("finished"), do: :finished
end
