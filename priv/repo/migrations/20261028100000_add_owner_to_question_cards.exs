defmodule MillenniumQuiz.Repo.Migrations.AddOwnerToQuestionCards do
  use Ecto.Migration

  # Whose card it is in the question: NULL for nobody, 1 or 2 for a player
  # (blue and red in the game). Existing rows stay NULL.
  def change do
    alter table(:question_cards) do
      add :owner, :integer
    end

    create constraint(:question_cards, :owner_is_a_player, check: "owner IN (1, 2)")
  end
end
