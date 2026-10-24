defmodule MillenniumQuiz.Quiz.Choice do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :text, :string
    field :correct, :boolean, default: false
  end

  @max_text_length 200

  def max_text_length, do: @max_text_length

  def changeset(choice, attrs) do
    choice
    |> cast(attrs, [:text, :correct])
    |> validate_required([:text])
    |> validate_length(:text, max: @max_text_length)
  end
end
