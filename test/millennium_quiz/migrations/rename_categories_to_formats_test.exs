defmodule MillenniumQuiz.Repo.Migrations.RenameCategoriesToFormatsTest do
  # Rolls migrations back and forward inside the test transaction (Postgres
  # DDL is transactional), so it needs the shared sandbox: not async.
  use MillenniumQuiz.DataCase, async: false

  alias MillenniumQuiz.Quiz.Format

  @version 20_261_003_100_000

  defp migrations, do: Application.app_dir(:millennium_quiz, "priv/repo/migrations")

  # The migrator loads the migration files again on every run.
  setup do
    Code.put_compiler_option(:ignore_module_conflict, true)
    on_exit(fn -> Code.put_compiler_option(:ignore_module_conflict, false) end)
  end

  test "keeps existing categories and their topics, and backfills the date" do
    Ecto.Migrator.run(Repo, migrations(), :down, to: @version, log: false, migration_lock: false)

    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO categories (name, inserted_at, updated_at) VALUES ('Old', now(), now()) RETURNING id"
      )

    Repo.query!(
      "INSERT INTO topics (category_id, name, position, inserted_at, updated_at) VALUES ($1, 'Monsters', 0, now(), now())",
      [id]
    )

    Ecto.Migrator.run(Repo, migrations(), :up, all: true, log: false, migration_lock: false)

    format = Format |> Repo.get!(id) |> Repo.preload(:topics)
    assert format.name == "Old"
    assert format.date == Date.utc_today()
    assert [%{name: "Monsters"}] = format.topics
  end

  test "can be rolled back to categories" do
    Ecto.Migrator.run(Repo, migrations(), :down, to: @version, log: false, migration_lock: false)

    assert %{rows: [[1]]} =
             Repo.query!(
               "SELECT count(*) FROM information_schema.tables WHERE table_name = 'categories'"
             )

    assert %{rows: [[0]]} =
             Repo.query!(
               "SELECT count(*) FROM information_schema.columns WHERE table_name = 'categories' AND column_name = 'date'"
             )
  end
end
