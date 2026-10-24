defmodule MillenniumQuiz.Release do
  @moduledoc """
  Tasks run inside the release, where Mix is not available:

      bin/millennium_quiz eval "MillenniumQuiz.Release.migrate()"
      bin/millennium_quiz eval 'MillenniumQuiz.Release.create_admin("name", "a long password")'
      bin/millennium_quiz eval "MillenniumQuiz.Release.seed()"
      bin/millennium_quiz eval "MillenniumQuiz.Release.refresh_cards()"
      bin/millennium_quiz eval 'MillenniumQuiz.Release.export_quiz("quiz-backup.json")'
      bin/millennium_quiz eval 'MillenniumQuiz.Release.import_quiz("quiz-backup.json")'
  """
  @app :millennium_quiz

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    maybe_bootstrap_admin()
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def create_admin(username, password) do
    with_repo(fn -> do_create_admin(username, password) end)
  end

  def seed do
    with_repo(fn -> Code.eval_file(Application.app_dir(@app, "priv/repo/seeds.exs")) end)
  end

  @doc "Fetches every card in the card pool again (new errata, stats, artworks)."
  def refresh_cards do
    {:ok, _} = Application.ensure_all_started(:req)

    with_repo(fn ->
      {refreshed, failed} = MillenniumQuiz.Cards.refresh_all()
      IO.puts("Refreshed #{refreshed} cards")
      if failed != [], do: IO.puts("Failed: #{Enum.join(failed, ", ")}")
    end)
  end

  @doc """
  Writes a backup of the quiz content (formats, topics, questions, choices,
  card links) to `path`. See `MillenniumQuiz.Quiz.Export`.
  """
  def export_quiz(path) do
    with_repo(fn ->
      File.write!(path, MillenniumQuiz.Quiz.Export.to_json())
      IO.puts("Wrote the quiz backup to #{path}")
    end)
  end

  @doc """
  Restores a backup file. Formats whose name exists are skipped; missing cards
  are fetched from the remote sources, one at a time.
  See `MillenniumQuiz.Quiz.Import`.
  """
  def import_quiz(path) do
    {:ok, _} = Application.ensure_all_started(:req)

    with_repo(fn ->
      case File.read(path) do
        {:ok, json} -> json |> MillenniumQuiz.Quiz.Import.run() |> print_import()
        {:error, reason} -> IO.puts("Could not read #{path}: #{:file.format_error(reason)}")
      end
    end)
  end

  @doc "The lines that describe the result of `Quiz.Import.run/2`."
  def import_report({:error, message}), do: ["Import failed: #{message}"]

  def import_report({:ok, s}) do
    [
      "Formats created: #{s.formats_created}, skipped (name exists): #{length(s.formats_skipped)}, " <>
        "failed: #{length(s.formats_failed)}",
      "Topics: #{s.topics}, questions: #{s.questions}",
      "Card links: #{s.cards_linked} linked, #{s.cards_missing} missing"
    ] ++
      Enum.map(s.formats_skipped, &"Skipped: #{&1}") ++
      Enum.map(s.formats_failed, fn {name, msg} -> "Failed: #{name}: #{msg}" end) ++
      Enum.map(s.warnings, &"Warning: #{&1}")
  end

  defp print_import(result), do: result |> import_report() |> Enum.each(&IO.puts/1)

  # Creates the first admin from ADMIN_USERNAME / ADMIN_PASSWORD when the
  # users table is still empty. Runs as part of `migrate`.
  defp maybe_bootstrap_admin do
    username = System.get_env("ADMIN_USERNAME")
    password = System.get_env("ADMIN_PASSWORD")

    if username && password do
      with_repo(fn ->
        if MillenniumQuiz.Repo.aggregate(MillenniumQuiz.Accounts.User, :count) == 0 do
          do_create_admin(username, password)
        end
      end)
    end
  end

  defp do_create_admin(username, password) do
    case MillenniumQuiz.Accounts.register_user(%{username: username, password: password}) do
      {:ok, user} ->
        IO.puts("Created admin #{user.username}")

      {:error, changeset} ->
        IO.puts("Could not create admin: #{inspect(changeset.errors)}")
    end
  end

  defp with_repo(fun) do
    load_app()
    {:ok, _} = Application.ensure_all_started(:bcrypt_elixir)

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn _repo -> fun.() end)
    end

    :ok
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    Application.ensure_loaded(@app)
  end
end
