defmodule MillenniumQuiz.Repo.Migrations.CreateCardPool do
  use Ecto.Migration

  def change do
    # Local copy of every card used in a question, so the remote sources are
    # only asked once per card.
    create table(:cards) do
      add :password, :integer, null: false
      add :konami_id, :integer
      add :yugipedia_page_id, :integer
      add :name, :string, null: false
      add :card_type, :string
      add :tcg_release_date, :date
      # language => current name / text
      add :names, :map, null: false, default: %{}
      add :texts, :map, null: false, default: %{}
      add :fetched_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cards, [:password])
    # the id every source agrees on (YGOPRODeck sometimes lists an artwork's id)
    create unique_index(:cards, [:konami_id], where: "konami_id IS NOT NULL")

    # Every printed text version (errata) per language.
    create table(:card_texts) do
      add :card_id, references(:cards, on_delete: :delete_all), null: false
      add :language, :string, null: false
      add :version, :integer, null: false
      add :text, :text, null: false
      add :set, :string
      add :released_on, :date
    end

    create unique_index(:card_texts, [:card_id, :language, :version])
  end
end
