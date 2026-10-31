defmodule MillenniumQuiz.Quiz.CardAvatarCrop do
  @moduledoc """
  Where the face sits in a card's artwork when the card is a profile picture,
  one row per card (the same wherever the card is used): the focus point `x`,
  `y` in percent of the artwork (0..100, 50 is the centre) and the `zoom` in
  percent (100..300, 150 is the default). A card without a row uses
  `Avatars.default_crop/0`; `Quiz.set_avatar_crop/2` never stores the default.
  """
  use Ecto.Schema

  @primary_key {:card_id, :id, autogenerate: false}
  schema "card_avatar_crops" do
    field :x, :integer
    field :y, :integer
    field :zoom, :integer

    belongs_to :card, MillenniumQuiz.Cards.Card, define_field: false
  end
end
