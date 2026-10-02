defmodule MillenniumQuiz.Repo.Migrations.CreateQuizTables do
  use Ecto.Migration

  def change do
    create table(:categories) do
      add :name, :string, null: false
      add :description, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:categories, [:name])

    create table(:topics) do
      add :category_id, references(:categories, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:topics, [:category_id])

    create table(:questions) do
      add :topic_id, references(:topics, on_delete: :delete_all), null: false
      add :text, :text, null: false
      # Difficulty rank inside the topic, 0 = easiest.
      add :position, :integer, null: false, default: 0
      # Optional override; nil means "derive from position".
      add :points, :integer
      add :choices, :map, null: false, default: "[]"

      timestamps(type: :utc_datetime)
    end

    create index(:questions, [:topic_id, :position])
  end
end
