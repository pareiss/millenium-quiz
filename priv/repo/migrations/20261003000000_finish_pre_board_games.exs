defmodule MillenniumQuiz.Repo.Migrations.FinishPreBoardGames do
  use Ecto.Migration

  # Snapshots from before the board modes ("Heart of the Cards" / "Level Up!")
  # can't be continued; mark them finished so they leave the "Continue" list.
  def up do
    execute "UPDATE games SET status = 'finished' WHERE status <> 'finished' AND NOT (state ? 'mode')"
  end

  def down, do: :ok
end
