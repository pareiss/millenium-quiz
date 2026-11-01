defmodule MillenniumQuiz.Repo.Migrations.AddBoardToQuestionsTest do
  # Rolls migrations back and forward inside the test transaction: not async.
  use MillenniumQuiz.DataCase, async: false

  @version 20_261_101_171_937

  defp migrations, do: Application.app_dir(:millennium_quiz, "priv/repo/migrations")

  setup do
    Code.put_compiler_option(:ignore_module_conflict, true)
    on_exit(fn -> Code.put_compiler_option(:ignore_module_conflict, false) end)
  end

  defp board_column do
    Repo.query!(
      "SELECT data_type, is_nullable FROM information_schema.columns WHERE table_name = 'questions' AND column_name = 'board'"
    ).rows
  end

  test "adds a nullable board column; rolling back drops it and keeps the questions" do
    Ecto.Migrator.run(Repo, migrations(), :down, to: @version, log: false, migration_lock: false)
    assert board_column() == []

    %{rows: [[fid]]} =
      Repo.query!(
        "INSERT INTO formats (name, date, inserted_at, updated_at) VALUES ('F', '2010-03-01', now(), now()) RETURNING id"
      )

    %{rows: [[tid]]} =
      Repo.query!(
        "INSERT INTO topics (format_id, name, position, inserted_at, updated_at) VALUES ($1, 'T', 0, now(), now()) RETURNING id",
        [fid]
      )

    Repo.query!(
      "INSERT INTO questions (topic_id, text, position, choices, inserted_at, updated_at) VALUES ($1, 'Q1', 0, '{}', now(), now())",
      [tid]
    )

    Ecto.Migrator.run(Repo, migrations(), :up, all: true, log: false, migration_lock: false)

    assert board_column() == [["jsonb", "YES"]]

    # the old question has no board, and a board can be written
    assert %{rows: [[nil]]} = Repo.query!("SELECT board FROM questions WHERE text = 'Q1'")

    Repo.query!("UPDATE questions SET board = '{\"v\": 1}' WHERE text = 'Q1'")
    assert %{rows: [[%{"v" => 1}]]} = Repo.query!("SELECT board FROM questions WHERE text = 'Q1'")

    Ecto.Migrator.run(Repo, migrations(), :down, to: @version, log: false, migration_lock: false)
    assert board_column() == []

    assert %{rows: [[1]]} =
             Repo.query!("SELECT count(*) FROM questions WHERE topic_id = $1", [tid])

    Ecto.Migrator.run(Repo, migrations(), :up, all: true, log: false, migration_lock: false)
    assert board_column() == [["jsonb", "YES"]]
  end
end
