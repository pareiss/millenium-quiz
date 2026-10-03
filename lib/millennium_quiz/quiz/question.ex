defmodule MillenniumQuiz.Quiz.Question do
  use Ecto.Schema
  import Ecto.Changeset

  alias MillenniumQuiz.Quiz.{Choice, QuestionCard}

  @min_choices 2
  @max_choices 6

  schema "questions" do
    field :text, :string
    # Difficulty rank inside the topic. 0 is the easiest question.
    field :position, :integer, default: 0
    # Optional manual override. When nil the points derive from the position.
    field :points, :integer

    embeds_many :choices, Choice, on_replace: :delete

    belongs_to :topic, MillenniumQuiz.Quiz.Topic

    # The cards the question is about, from the card pool.
    has_many :question_cards, QuestionCard,
      preload_order: [asc: :position],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc "Points for a position in the list: 10 for the easiest, then +10 per step."
  def default_points(position), do: (position + 1) * 10

  @doc "The points a question is worth: the override if set, else the default."
  def effective_points(%__MODULE__{points: points}) when is_integer(points), do: points
  def effective_points(%__MODULE__{position: position}), do: default_points(position)

  def changeset(question, attrs) do
    question
    |> cast(attrs, [:text, :points])
    |> validate_required([:text])
    |> validate_length(:text, max: 1000)
    |> validate_number(:points, greater_than: 0, less_than_or_equal_to: 10_000)
    |> cast_embed(:choices,
      required: true,
      sort_param: :choices_sort,
      drop_param: :choices_drop
    )
    |> validate_choices()
  end

  @doc "Sets the question's cards, in order, from card pool ids."
  def put_cards(changeset, card_ids) do
    question_cards =
      card_ids
      |> Enum.uniq()
      |> Enum.with_index()
      |> Enum.map(fn {card_id, position} ->
        QuestionCard.changeset(%QuestionCard{}, %{card_id: card_id, position: position})
      end)

    put_assoc(changeset, :question_cards, question_cards)
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
