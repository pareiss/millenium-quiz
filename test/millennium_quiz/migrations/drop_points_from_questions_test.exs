defmodule MillenniumQuiz.Repo.Migrations.DropPointsFromQuestionsTest do
  # Rolls migrations back and forward inside the test transaction: not async.
  use MillenniumQuiz.DataCase, async: false

  @version 20_261_031_230_639

  defp migrations, do: Application.app_dir(:millennium_quiz, "priv/repo/migrations")

  setup do
    Code.put_compiler_option(:ignore_module_conflict, true)
    on_exit(fn -> Code.put_compiler_option(:ignore_module_conflict, false) end)
  end

  defp points_column? do
    %{rows: [[n]]} =
      Repo.query!(
        "SELECT count(*) FROM information_schema.columns WHERE table_name = 'questions' AND column_name = 'points'"
      )

    n == 1
  end

  test "rolls back to a nullable points column, and drops it again keeping the questions" do
    Ecto.Migrator.run(Repo, migrations(), :down, to: @version, log: false, migration_lock: false)
    assert points_column?()

    %{rows: [[fid]]} =
      Repo.query!(
        "INSERT INTO formats (name, date, inserted_at, updated_at) VALUES ('F', '2010-03-01', now(), now()) RETURNING id"
      )

    %{rows: [[tid]]} =
      Repo.query!(
        "INSERT INTO topics (format_id, name, position, inserted_at, updated_at) VALUES ($1, 'T', 0, now(), now()) RETURNING id",
        [fid]
      )

    # nullable: a question without points can be inserted
    Repo.query!(
      "INSERT INTO questions (topic_id, text, position, points, choices, inserted_at, updated_at) VALUES ($1, 'Q1', 0, 55, '{}', now(), now()), ($1, 'Q2', 1, NULL, '{}', now(), now())",
      [tid]
    )

    Ecto.Migrator.run(Repo, migrations(), :up, all: true, log: false, migration_lock: false)

    refute points_column?()

    assert %{rows: [[2]]} =
             Repo.query!("SELECT count(*) FROM questions WHERE topic_id = $1", [tid])
  end
end
