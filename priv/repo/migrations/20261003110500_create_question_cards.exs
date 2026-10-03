defmodule MillenniumQuiz.Repo.Migrations.CreateQuestionCards do
  use Ecto.Migration

  # The cards a question is about, from the card pool, in display order.
  def change do
    create table(:question_cards) do
      add :question_id, references(:questions, on_delete: :delete_all), null: false
      add :card_id, references(:cards, on_delete: :restrict), null: false
      add :position, :integer, null: false, default: 0
    end

    create unique_index(:question_cards, [:question_id, :card_id])
    create index(:question_cards, [:card_id])
  end
end
