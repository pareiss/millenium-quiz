defmodule MillenniumQuiz.Repo.Migrations.AddCardDetailsAndArtworks do
  use Ecto.Migration

  # Everything needed to draw a card locally: frame, stats, spell/trap
  # property and the artwork (without the printed text, which changes with
  # errata and comes from card_texts).
  def change do
    alter table(:cards) do
      # Monster / Spell / Trap
      add :kind, :string
      # Spells and Traps: Normal, Quick-Play, Continuous, Field, Equip, Ritual, Counter
      add :property, :string
      # YGOPRODeck frame, e.g. "effect", "xyz_pendulum", "spell"
      add :frame_type, :string
      # e.g. "Dragon / Xyz / Pendulum / Effect"
      add :monster_type_line, :string
      add :attribute, :string
      add :level, :integer
      add :rank, :integer
      add :link_arrows, {:array, :string}, null: false, default: []
      # strings because some cards print "?"
      add :atk, :string
      add :def, :string
      add :pendulum_scale, :integer
      add :materials, :string
      # language => current Pendulum Effect
      add :pendulum_texts, :map, null: false, default: %{}
      add :archetypes, {:array, :string}, null: false, default: []
    end

    create table(:card_artworks) do
      add :card_id, references(:cards, on_delete: :delete_all), null: false
      # id of the artwork (alternate artworks have their own)
      add :artwork_id, :integer, null: false
      add :content_type, :string, null: false
      add :data, :binary, null: false
      add :source_url, :string, null: false
      add :fetched_at, :utc_datetime, null: false
    end

    create unique_index(:card_artworks, [:card_id])
  end
end
