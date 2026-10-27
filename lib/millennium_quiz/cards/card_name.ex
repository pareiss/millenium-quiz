defmodule MillenniumQuiz.Cards.CardName do
  @moduledoc """
  One row of the list of all TCG card names (`MillenniumQuiz.Cards.CardNames`):
  what YGOPRODeck's search answers with, kept locally.
  """
  use Ecto.Schema

  schema "card_names" do
    field :password, :integer
    field :passwords, {:array, :integer}, default: []
    field :konami_id, :integer
    field :name, :string
    field :card_type, :string
    field :frame_type, :string
    field :tcg_release_date, :date

    timestamps(type: :utc_datetime)
  end
end
