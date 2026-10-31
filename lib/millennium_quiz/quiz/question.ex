defmodule MillenniumQuiz.Quiz.Question do
  use Ecto.Schema
  import Ecto.Changeset

  alias MillenniumQuiz.Quiz.{Choice, QuestionCard}

  @min_choices 2
  @max_choices 6
  @max_text_length 1000
  @max_submitter_length 30

  schema "questions" do
    field :text, :string
    # Difficulty rank inside the topic. 0 is the easiest question.
    field :position, :integer, default: 0
    # Optional manual override. When nil the points derive from the position.
    field :points, :integer
    # Name of the player who suggested the question, if it came from one.
    field :submitted_by, :string

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

  @doc "Points for a position in the list: 10 for the easiest, then +10 per step."
  def default_points(position), do: (position + 1) * 10

  @doc "The points a question is worth: the override if set, else the default."
  def effective_points(%__MODULE__{points: points}) when is_integer(points), do: points
  def effective_points(%__MODULE__{position: position}), do: default_points(position)

  @max_damage 3000

  @doc """
  The life points a wrong answer costs: (position + 1)^2 * 100 for a 0-based
  position, at most 3000. 100, 400, 900, 1600, 2500, 3000, 3000...
  """
  def damage(position) when is_integer(position) and position >= 0,
    do: min((position + 1) * (position + 1) * 100, @max_damage)

  def changeset(question, attrs) do
    question
    |> cast(attrs, [:text, :points, :submitted_by])
    |> update_change(:submitted_by, &blank_to_nil/1)
    |> validate_required([:text])
    |> validate_length(:text, max: @max_text_length)
    |> validate_length(:submitted_by, max: @max_submitter_length)
    |> validate_number(:points, greater_than: 0, less_than_or_equal_to: 10_000)
    |> cast_embed(:choices,
      required: true,
      sort_param: :choices_sort,
      drop_param: :choices_drop
    )
    |> validate_choices()
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
