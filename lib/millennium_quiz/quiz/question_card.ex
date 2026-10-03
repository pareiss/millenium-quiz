defmodule MillenniumQuiz.Quiz.QuestionCard do
  @moduledoc "A card a question is about, in display order."
  use Ecto.Schema
  import Ecto.Changeset

  schema "question_cards" do
    field :position, :integer, default: 0

    belongs_to :question, MillenniumQuiz.Quiz.Question
    belongs_to :card, MillenniumQuiz.Cards.Card
  end

  @doc "A card at a position; a card can be on a question only once."
  def changeset(question_card, attrs) do
    question_card
    |> change(attrs)
    |> unique_constraint([:question_id, :card_id])
  end
end
