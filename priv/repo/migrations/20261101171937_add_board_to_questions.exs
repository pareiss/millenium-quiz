defmodule MillenniumQuiz.Repo.Migrations.AddBoardToQuestions do
  use Ecto.Migration

  # A nullable column without a default: no table rewrite and no data change,
  # so it is safe on a database with data. Rolling back drops the boards.
  def change do
    alter table(:questions) do
      add :board, :map
    end
  end
end
