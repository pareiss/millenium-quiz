defmodule MillenniumQuiz.Repo.Migrations.CreateCardNames do
  use Ecto.Migration

  # Every card released in the TCG, by name: the list the card search looks in
  # before it asks YGOPRODeck (see MillenniumQuiz.Cards.CardNames). Not the card
  # pool: a row here has no texts and no artwork, and nothing references it.
  def change do
    create table(:card_names) do
      add :password, :bigint, null: false
      # every artwork's id, the printed password among them
      add :passwords, {:array, :bigint}, null: false, default: []
      add :konami_id, :bigint
      add :name, :string, null: false
      add :card_type, :string
      add :frame_type, :string
      add :tcg_release_date, :date

      timestamps(type: :utc_datetime)
    end

    create unique_index(:card_names, [:password])
    create index(:card_names, [:konami_id])
  end
end
