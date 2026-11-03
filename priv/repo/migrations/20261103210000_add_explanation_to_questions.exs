defmodule MillenniumQuiz.Repo.Migrations.AddExplanationToQuestions do
  use Ecto.Migration

  # A nullable column without a default: no table rewrite and no data change,
  # so it is safe on a database with data. Rolling back drops the explanations.
  def change do
    alter table(:questions) do
      add :explanation, :text
    end
  end
end
