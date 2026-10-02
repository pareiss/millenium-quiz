defmodule MillenniumQuiz.Quiz.QuestionCard do
  @moduledoc "A card a question is about, in display order."
  use Ecto.Schema

  schema "question_cards" do
    field :position, :integer, default: 0

    belongs_to :question, MillenniumQuiz.Quiz.Question
    belongs_to :card, MillenniumQuiz.Cards.Card
  end
end
