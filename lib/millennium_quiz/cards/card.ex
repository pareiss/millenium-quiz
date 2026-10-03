defmodule MillenniumQuiz.Cards.Card do
  @moduledoc "A card in the local card pool, identified by its Konami password."
  use Ecto.Schema

  alias MillenniumQuiz.Cards.CardText

  schema "cards" do
    field :password, :integer
    field :konami_id, :integer
    field :yugipedia_page_id, :integer
    field :name, :string
    field :card_type, :string
    field :tcg_release_date, :date
    field :names, :map, default: %{}
    field :texts, :map, default: %{}
    field :fetched_at, :utc_datetime

    has_many :card_texts, CardText,
      preload_order: [asc: :language, asc: :version],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end
end
