defmodule MillenniumQuiz.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :category_id, references(:categories, on_delete: :nilify_all)
      add :status, :string, null: false, default: "active"
      add :state, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:games, [:status, :updated_at])
  end
end
