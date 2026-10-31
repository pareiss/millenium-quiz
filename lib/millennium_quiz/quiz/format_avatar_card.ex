defmodule MillenniumQuiz.Quiz.FormatAvatarCard do
  @moduledoc """
  A card an admin chose as one of the profile pictures of a format, in
  display order (`position`). A card is in a format's list only once.
  """
  use Ecto.Schema

  schema "format_avatar_cards" do
    field :position, :integer, default: 0

    belongs_to :format, MillenniumQuiz.Quiz.Format
    belongs_to :card, MillenniumQuiz.Cards.Card
  end
end
