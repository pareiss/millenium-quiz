defmodule MillenniumQuiz.Quiz.Question do
  use Ecto.Schema
  import Ecto.Changeset

  alias MillenniumQuiz.Quiz.{Board, Choice, QuestionCard}

  @min_choices 2
  @max_choices 6
  @max_text_length 1000
  @max_submitter_length 30

  schema "questions" do
    field :text, :string
    # Difficulty rank inside the topic. 0 is the easiest question.
    field :position, :integer, default: 0
    # Name of the player who suggested the question, if it came from one.
    field :submitted_by, :string
    # A read-only board shown with the question (`Quiz.Board`), or nil.
    field :board, :map

    embeds_many :choices, Choice, on_replace: :delete

    belongs_to :topic, MillenniumQuiz.Quiz.Topic

    # The cards the question is about, from the card pool.
    has_many :question_cards, QuestionCard,
      preload_order: [asc: :position],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def min_choices, do: @min_choices
  def max_choices, do: @max_choices
  def max_text_length, do: @max_text_length
  def max_submitter_length, do: @max_submitter_length

  @max_damage 3000

  @doc """
  The life points a wrong answer costs: (position + 1)^2 * 100 for a 0-based
  position, at most 3000. 100, 400, 900, 1600, 2500, 3000, 3000...
  """
  def damage(position) when is_integer(position) and position >= 0,
    do: min((position + 1) * (position + 1) * 100, @max_damage)

  def changeset(question, attrs) do
    question
    |> cast(attrs, [:text, :submitted_by])
    |> update_change(:submitted_by, &blank_to_nil/1)
    |> validate_required([:text])
    |> validate_length(:text, max: @max_text_length)
    |> validate_length(:submitted_by, max: @max_submitter_length)
    |> cast_embed(:choices,
      required: true,
      sort_param: :choices_sort,
      drop_param: :choices_drop
    )
    |> validate_choices()
    |> cast_board(attrs)
  end

  @doc """
  Validates the question's board against its format: every card in the pool and
  released by the format's date, no zone the Master Rule lacks. `date` is the
  format's date (or nil). Adds one error on `:board` per problem, each naming
  the zone. Use `Board.validate/2` and `Board.missing_passwords/1` for the
  cards an importer could fetch.
  """
  def validate_board_for_format(changeset, date) do
    # A board that failed to cast has no change; get_field would then return the
    # old stored board and its errors would mix with the shape errors.
    board =
      if Keyword.has_key?(changeset.errors, :board), do: nil, else: get_field(changeset, :board)

    case board do
      nil ->
        changeset

      board ->
        case Board.validate(board, date) do
          :ok -> changeset
          {:error, issues} -> add_board_errors(changeset, issues)
        end
    end
  end

  # The board comes from the admin form as a map (or pasted JSON); the key may
  # be an atom or a string. A missing key leaves the board as it is, null or an
  # empty string removes it.
  defp cast_board(changeset, attrs) do
    case fetch_board(attrs) do
      :error ->
        changeset

      {:ok, empty} when empty in [nil, ""] ->
        put_change(changeset, :board, nil)

      {:ok, input} ->
        case Board.cast(input) do
          {:ok, board} -> put_change(changeset, :board, board)
          {:error, issues} -> add_board_errors(changeset, issues)
        end
    end
  end

  defp fetch_board(attrs) do
    case Map.fetch(attrs, "board") do
      :error -> Map.fetch(attrs, :board)
      found -> found
    end
  end

  defp add_board_errors(changeset, issues) do
    Enum.reduce(issues, changeset, fn issue, acc ->
      add_error(acc, :board, "#{issue.path}: #{issue.message}", kind: issue.kind)
    end)
  end

  @doc """
  Sets the question's cards, in order. An entry is a card pool id, or
  `{id, owner}` with the owner 1, 2 or nil (a bare id has no owner). A card
  listed twice counts once, the first entry wins.
  """
  def put_cards(changeset, entries) do
    question_cards =
      entries
      |> Enum.map(fn
        {card_id, owner} -> {card_id, owner}
        card_id -> {card_id, nil}
      end)
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.with_index()
      |> Enum.map(fn {{card_id, owner}, position} ->
        QuestionCard.changeset(%QuestionCard{}, %{
          card_id: card_id,
          owner: owner,
          position: position
        })
      end)

    put_assoc(changeset, :question_cards, question_cards)
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(s) do
    case String.trim(s) do
      "" -> nil
      s -> s
    end
  end

  defp validate_choices(changeset) do
    choices = get_embed(changeset, :choices, :struct)
    correct = Enum.count(choices, & &1.correct)

    cond do
      length(choices) not in @min_choices..@max_choices ->
        add_error(changeset, :choices, "must have between %{min} and %{max} answers",
          min: @min_choices,
          max: @max_choices
        )

      correct != 1 ->
        add_error(changeset, :choices, "exactly one answer must be marked as correct")

      true ->
        changeset
    end
  end
end
