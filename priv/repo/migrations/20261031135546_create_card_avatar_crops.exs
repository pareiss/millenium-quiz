defmodule MillenniumQuiz.Repo.Migrations.CreateCardAvatarCrops do
  use Ecto.Migration

  # Where the face sits in a card's artwork when the card is a profile
  # picture: the focus point (x, y) in percent of the artwork (50 = centre)
  # and the zoom in percent (150 = the default). No row means the default.
  # Deleting the card removes its crop.
  def change do
    create table(:card_avatar_crops, primary_key: false) do
      add :card_id, references(:cards, on_delete: :delete_all), primary_key: true, null: false
      add :x, :integer, null: false
      add :y, :integer, null: false
      add :zoom, :integer, null: false
    end

    create constraint(:card_avatar_crops, :x_in_range, check: "x >= 0 AND x <= 100")
    create constraint(:card_avatar_crops, :y_in_range, check: "y >= 0 AND y <= 100")
    create constraint(:card_avatar_crops, :zoom_in_range, check: "zoom >= 100 AND zoom <= 300")
  end
end
