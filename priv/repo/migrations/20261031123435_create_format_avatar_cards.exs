defmodule MillenniumQuiz.Repo.Migrations.CreateFormatAvatarCards do
  use Ecto.Migration

  # The cards an admin chose as the profile pictures of a format. Deleting
  # the format or the card removes the row (a picture is no reason to keep a
  # card, unlike a question about it).
  def change do
    create table(:format_avatar_cards) do
      add :format_id, references(:formats, on_delete: :delete_all), null: false
      add :card_id, references(:cards, on_delete: :delete_all), null: false
      add :position, :integer, null: false, default: 0
    end

    # Also serves the lookups by format_id (its leading column).
    create unique_index(:format_avatar_cards, [:format_id, :card_id])
  end
end
