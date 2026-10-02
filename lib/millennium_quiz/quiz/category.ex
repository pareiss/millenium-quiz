defmodule MillenniumQuiz.Quiz.Category do
  use Ecto.Schema
  import Ecto.Changeset

  alias MillenniumQuiz.Quiz.Topic

  @min_topics 2
  @max_topics 6

  schema "categories" do
    field :name, :string
    field :description, :string

    has_many :topics, Topic, preload_order: [asc: :position], on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def min_topics, do: @min_topics
  def max_topics, do: @max_topics

  @doc """
  Topics are edited inline with the category. `topics_sort` / `topics_drop`
  are the params produced by `<.inputs_for>` add/remove buttons; the position
  of each topic follows its index in the form.
  """
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> cast_assoc(:topics,
      with: &Topic.changeset/3,
      sort_param: :topics_sort,
      drop_param: :topics_drop
    )
    |> validate_topic_count()
    |> unique_constraint(:name)
  end

  # `validate_length/3` only runs when the association changed, but a
  # category must always have 2-6 topics, so this checks the final list.
  defp validate_topic_count(changeset) do
    count = changeset |> get_assoc(:topics, :struct) |> length()

    if count in @min_topics..@max_topics do
      changeset
    else
      add_error(changeset, :topics, "must have between %{min} and %{max} topics",
        min: @min_topics,
        max: @max_topics,
        count: count
      )
    end
  end
end
