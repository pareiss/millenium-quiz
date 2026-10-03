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
  Picks stay hidden until the reveal, and everyone who was right scores.

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
  """

  alias MillenniumQuiz.Cards
  alias MillenniumQuiz.Quiz.Question

  @min_players 2
  @max_players 4
  @modes [:free, :ascending]

  defstruct format_id: nil,
            format_name: nil,
            format_date: nil,
            mode: :free,
            players: [],
            topics: [],
            questions: [],
            round: 1,
            turn_order: [],
            turn_index: 0,
            current: nil,
            picks: [],
            answered: 0,
            phase: :choosing

  @type mode :: :free | :ascending
  @type player :: %{name: String.t(), score: non_neg_integer()}
  @type result :: %{chooser: non_neg_integer(), picks: [non_neg_integer()]}
  @type question :: %{
          id: integer(),
          topic: String.t(),
          column: non_neg_integer(),
          text: String.t(),
          points: pos_integer(),
          choices: [String.t()],
          correct: non_neg_integer(),
          cards: [card()],
          result: result() | nil
        }
  @type card :: %{name: String.t(), text: String.t(), set: String.t() | nil}
  @type t :: %__MODULE__{
          format_id: integer() | nil,
          format_name: String.t() | nil,
          format_date: Date.t() | nil,
          mode: mode(),
          players: [player()],
          topics: [String.t()],
          questions: [question()],
          round: pos_integer(),
          turn_order: [non_neg_integer()],
          turn_index: non_neg_integer(),
          current: non_neg_integer() | nil,
          picks: [non_neg_integer() | nil],
          answered: non_neg_integer(),
          phase: :choosing | :answering | :revealed | :finished
        }

  def min_players, do: @min_players
  def max_players, do: @max_players
  def modes, do: @modes

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

  @doc """
  Creates a game from a format, player names and `Question` structs
  (with `:topic` preloaded).

  Options:
    * `:mode` - `:free` (default) or `:ascending`.
    * `:shuffle` - function used for every random decision, defaults to
      `Enum.shuffle/1`. Tests pass `& &1` to make games deterministic.
  """
  def new(format, player_names, questions, opts \\ []) do
    shuffle = Keyword.get(opts, :shuffle, &Enum.shuffle/1)
    names = Enum.map(player_names, &String.trim/1)
    mode = parse_mode(Keyword.get(opts, :mode, :free))

    cond do
      mode == {:error, :invalid_mode} ->
        mode

      length(names) not in @min_players..@max_players ->
        {:error, :invalid_player_count}

      Enum.any?(names, &(&1 == "")) ->
        {:error, :blank_player_name}

      questions == [] ->
        {:error, :no_questions}

      true ->
        {:ok, mode} = mode
        {topics, questions} = build_board(questions, format.date)

        {:ok,
         %__MODULE__{
           format_id: format.id,
           format_name: format.name,
           format_date: format.date,
           mode: mode,
           players: Enum.map(names, &%{name: &1, score: 0}),
           topics: topics,
           questions: questions,
           picks: List.duplicate(nil, length(names)),
           turn_order: shuffle.(Enum.to_list(0..(length(names) - 1)))
         }}
    end
  end

  # Columns in topic order, each column from easiest to hardest.
  defp build_board(questions, date) do
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
        |> Enum.map(&snapshot_question(&1, index, date))
      end)

    {topics, questions}
  end

  defp snapshot_question(%Question{} = q, column, date) do
    %{
      id: q.id,
      topic: q.topic.name,
      column: column,
      text: q.text,
      points: Question.effective_points(q),
      choices: Enum.map(q.choices, & &1.text),
      correct: Enum.find_index(q.choices, & &1.correct),
      cards: snapshot_cards(q.question_cards, date),
      result: nil
    }
  end

  # Card texts as they read on the format's date (English for now).
  defp snapshot_cards(%Ecto.Association.NotLoaded{}, _date), do: []

  defp snapshot_cards(question_cards, date) do
    for %{card: card} <- question_cards do
      %{text: text, set: set} = Cards.text_on(card, date)
      %{name: card.name, text: text, set: set}
    end
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

  @doc "The players in the order they answer this round, chooser first."
  def answer_order(%__MODULE__{turn_order: order, turn_index: index}),
    do: Enum.drop(order, index) ++ Enum.take(order, index)

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

  @doc "How many players answered an answered question correctly."
  def correct_count(%{result: %{picks: picks}, correct: correct}),
    do: Enum.count(picks, &(&1 == correct))

  @doc "Players sorted by score, highest first, with their index."
  def standings(%__MODULE__{players: players}) do
    players
    |> Enum.with_index()
    |> Enum.sort_by(fn {player, index} -> {-player.score, index} end)
  end

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
    if game.answered < length(game.players) do
      game
    else
      question = current_question(game)

      players =
        game.players
        |> Enum.zip(game.picks)
        |> Enum.map(fn {player, pick} ->
          if pick == question.correct,
            do: %{player | score: player.score + question.points},
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

  @doc "Passes the turn to the next player, or finishes when the board is empty."
  def next_round(%__MODULE__{phase: :revealed} = game) do
    if Enum.all?(game.questions, & &1.result) do
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
           turn_index: rem(game.turn_index + 1, length(game.turn_order))
       }}
    end
  end

  def next_round(%__MODULE__{}), do: {:error, :not_revealed}

  @doc "Ends the game early. A question that is not revealed yet is not scored."
  def finish(%__MODULE__{} = game), do: {:ok, %{game | phase: :finished}}

  ## Serialization (stored as JSONB in `games.state`)

  def to_map(%__MODULE__{} = game) do
    game
    |> Map.from_struct()
    |> Map.update!(:phase, &Atom.to_string/1)
    |> Map.update!(:mode, &Atom.to_string/1)
  end

  # Snapshots from before the board modes have no "mode"; they open as finished.
  def from_map(%{"mode" => _} = map) do
    {:ok, mode} = parse_mode(map["mode"])
    no_picks = List.duplicate(nil, length(map["players"]))

    %__MODULE__{
      format_id: map["format_id"] || map["category_id"],
      format_name: map["format_name"] || map["category_name"],
      format_date: date_from_map(map["format_date"]),
      mode: mode,
      players: players_from_map(map["players"]),
      topics: map["topics"],
      questions:
        Enum.map(map["questions"], fn q ->
          %{
            id: q["id"],
            topic: q["topic"],
            column: q["column"],
            text: q["text"],
            points: q["points"],
            choices: q["choices"],
            correct: q["correct"],
            cards:
              Enum.map(q["cards"] || [], &%{name: &1["name"], text: &1["text"], set: &1["set"]}),
            result: q["result"] && result_from_map(q["result"], no_picks)
          }
        end),
      round: map["round"],
      turn_order: map["turn_order"],
      turn_index: map["turn_index"],
      current: map["current"],
      picks: map["picks"] || no_picks,
      answered: map["answered"] || 0,
      phase: phase_from_string(map["phase"])
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

  defp result_from_map(%{"picks" => picks} = result, _no_picks),
    do: %{chooser: result["chooser"], picks: picks}

  # Early board games, where only the chooser answered.
  defp result_from_map(%{"player" => player, "pick" => pick}, no_picks),
    do: %{chooser: player, picks: List.replace_at(no_picks, player, pick)}

  # Snapshots from before categories became formats have `category_*` keys
  # and no date.
  defp date_from_map(nil), do: nil
  defp date_from_map(date), do: Date.from_iso8601!(date)

  defp players_from_map(players), do: Enum.map(players, &%{name: &1["name"], score: &1["score"]})

  defp phase_from_string("choosing"), do: :choosing
  defp phase_from_string("answering"), do: :answering
  defp phase_from_string("revealed"), do: :revealed
  defp phase_from_string("finished"), do: :finished
end
