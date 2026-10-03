defmodule MillenniumQuiz.Repo.Migrations.RenameCategoriesToFormats do
  use Ecto.Migration

  def change do
    rename table(:categories), to: table(:formats)
    rename table(:topics), :category_id, to: :format_id
    rename table(:games), :category_id, to: :format_id

    rename index(:categories, [:name], name: :categories_name_index),
      to: "formats_name_index"

    rename index(:topics, [:category_id], name: :topics_category_id_index),
      to: "topics_format_id_index"

    execute "ALTER TABLE formats RENAME CONSTRAINT categories_pkey TO formats_pkey",
            "ALTER TABLE formats RENAME CONSTRAINT formats_pkey TO categories_pkey"

    execute "ALTER TABLE topics RENAME CONSTRAINT topics_category_id_fkey TO topics_format_id_fkey",
            "ALTER TABLE topics RENAME CONSTRAINT topics_format_id_fkey TO topics_category_id_fkey"

    execute "ALTER TABLE games RENAME CONSTRAINT games_category_id_fkey TO games_format_id_fkey",
            "ALTER TABLE games RENAME CONSTRAINT games_format_id_fkey TO games_category_id_fkey"

    execute "ALTER SEQUENCE categories_id_seq RENAME TO formats_id_seq",
            "ALTER SEQUENCE formats_id_seq RENAME TO categories_id_seq"

    # A format is a point in time; existing rows start at the migration date,
    # i.e. "card texts as of today". Admins set the real date when they edit a
    # format (new formats always get one, it is required).
    alter table(:formats) do
      add :date, :date
    end

    execute "UPDATE formats SET date = CURRENT_DATE", ""

    alter table(:formats) do
      modify :date, :date, null: false, from: {:date, null: true}
    end
  end
end
