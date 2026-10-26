defmodule MillenniumQuiz.Repo.Migrations.CreateQuestionSubmissions do
  use Ecto.Migration

  # Questions suggested by players. A submission is written once and never
  # edited; an admin reviews it and, on approval, creates a normal question
  # (`question_id`) from it.
  def change do
    create table(:question_submissions) do
      add :topic_id, references(:topics, on_delete: :delete_all), null: false
      add :token, :string, null: false
      add :text, :text, null: false
      add :choices, {:array, :map}, null: false, default: []
      add :submitter_name, :string
      add :status, :string, null: false, default: "pending"
      add :question_id, references(:questions, on_delete: :nilify_all)
      add :reviewed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:question_submissions, [:token])
    create index(:question_submissions, [:status, :inserted_at])
    create index(:question_submissions, [:topic_id])
    create index(:question_submissions, [:question_id])

    alter table(:questions) do
      # Name the player gave when suggesting the question; shown on the reveal.
      add :submitted_by, :string
    end
  end
end
