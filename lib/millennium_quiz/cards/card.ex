defmodule MillenniumQuiz.Cards.Card do
  @moduledoc "A card in the local card pool, identified by its Konami password."
  use Ecto.Schema

  alias MillenniumQuiz.Cards.{CardArtwork, CardText}

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

    # What is printed on the card besides its text
    field :kind, :string
    field :property, :string
    field :frame_type, :string
    field :monster_type_line, :string
    field :attribute, :string
    field :level, :integer
    field :rank, :integer
    field :link_arrows, {:array, :string}, default: []
    field :atk, :string
    field :def, :string
    field :pendulum_scale, :integer
    field :materials, :string
    field :pendulum_texts, :map, default: %{}
    field :archetypes, {:array, :string}, default: []

    # Kept out of the default preloads: it is a ~130 KB image.
    has_one :artwork, CardArtwork, on_replace: :delete

    has_many :card_texts, CardText,
      preload_order: [asc: :language, asc: :version],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end
end
