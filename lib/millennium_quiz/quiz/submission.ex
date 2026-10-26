defmodule MillenniumQuiz.Quiz.Submission do
  @moduledoc """
  A question suggested by a player, waiting for an admin.

  The player's text, answers and name are written once (`changeset/2`) and
  never edited afterwards; only the review (`status`, `question_id`,
  `reviewed_at`) changes. Approving creates a separate `Question`, so
  unreviewed input never sits in the table games are built from.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MillenniumQuiz.Quiz.{Choice, Question}

  @max_name_length 30
  @statuses ~w(pending approved rejected)

  schema "question_submissions" do
    field :token, :string
    field :text, :string
    embeds_many :choices, Choice, on_replace: :delete
    field :submitter_name, :string
    field :status, :string, default: "pending"
    field :reviewed_at, :utc_datetime

    belongs_to :topic, MillenniumQuiz.Quiz.Topic
    belongs_to :question, Question

    timestamps(type: :utc_datetime)
  end

  def max_name_length, do: @max_name_length
  def statuses, do: @statuses

  @doc "Validates what a player sends. The topic and token are set by the caller."
  def changeset(submission, attrs) do
    submission
    |> cast(attrs, [:text, :submitter_name])
    |> update_change(:text, &String.trim/1)
    |> update_change(:submitter_name, &blank_to_nil/1)
    |> validate_required([:text])
    |> validate_length(:text, max: Question.max_text_length())
    |> validate_length(:submitter_name, max: @max_name_length)
    |> cast_embed(:choices,
      required: true,
      sort_param: :choices_sort,
      drop_param: :choices_drop
    )
    |> validate_choices()
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
      length(choices) not in Question.min_choices()..Question.max_choices() ->
        add_error(changeset, :choices, "must have between %{min} and %{max} answers",
          min: Question.min_choices(),
          max: Question.max_choices()
        )

      correct != 1 ->
        add_error(changeset, :choices, "exactly one answer must be marked as correct")

      true ->
        changeset
    end
  end
end
