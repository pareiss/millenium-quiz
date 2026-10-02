defmodule MillenniumQuiz.Cards.CardText do
  @moduledoc """
  One printed text version of a card in one language. `set` is the product
  the version was first printed in, `released_on` that product's release
  date in the language's region (nil when unknown).
  """
  use Ecto.Schema

  schema "card_texts" do
    field :language, :string
    field :version, :integer
    field :text, :string
    field :set, :string
    field :released_on, :date

    belongs_to :card, MillenniumQuiz.Cards.Card
  end
end
