defmodule MillenniumQuiz.Cards.CardArtwork do
  @moduledoc """
  The artwork of a card (the picture only, without frame or text), stored
  locally so cards can be drawn with the text of any format's date.
  Downloaded once from YGOPRODeck, which asks not to hotlink its images.
  """
  use Ecto.Schema

  schema "card_artworks" do
    field :artwork_id, :integer
    field :content_type, :string
    field :data, :binary
    field :source_url, :string
    field :fetched_at, :utc_datetime

    belongs_to :card, MillenniumQuiz.Cards.Card
  end
end
