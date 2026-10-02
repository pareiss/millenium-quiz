defmodule MillenniumQuiz.Games.GameRecord do
  @moduledoc "Persisted snapshot of a `MillenniumQuiz.Game`."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :id

  schema "games" do
    field :status, Ecto.Enum, values: [:active, :paused, :finished], default: :active
    field :state, :map

    belongs_to :category, MillenniumQuiz.Quiz.Category

    timestamps(type: :utc_datetime)
  end
end
