defmodule MillenniumQuiz.Repo.Migrations.DropPointsFromQuestions do
  use Ecto.Migration

  # Games use a fixed damage per position; the per-question override is dead.
  # Existing values are dropped; rolling back adds an empty nullable column.
  def change do
    alter table(:questions) do
      remove :points, :integer
    end
  end
end
