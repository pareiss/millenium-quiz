defmodule MillenniumQuiz.Quiz.Topic do
  use Ecto.Schema
  import Ecto.Changeset

  schema "topics" do
    field :name, :string
    field :position, :integer, default: 0

    belongs_to :format, MillenniumQuiz.Quiz.Format
    has_many :questions, MillenniumQuiz.Quiz.Question, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc "Used through `cast_assoc` on the format; `position` is the form index."
  def changeset(topic, attrs, position) do
    topic
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> put_change(:position, position)
  end
end
