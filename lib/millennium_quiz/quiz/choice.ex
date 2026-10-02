defmodule MillenniumQuiz.Quiz.Choice do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :text, :string
    field :correct, :boolean, default: false
  end

  def changeset(choice, attrs) do
    choice
    |> cast(attrs, [:text, :correct])
    |> validate_required([:text])
    |> validate_length(:text, max: 200)
  end
end
