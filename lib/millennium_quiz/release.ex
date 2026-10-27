defmodule MillenniumQuiz.Release do
  @moduledoc """
  Tasks run inside the release, where Mix is not available:

      bin/millennium_quiz eval "MillenniumQuiz.Release.migrate()"
      bin/millennium_quiz eval 'MillenniumQuiz.Release.create_admin("name", "a long password")'
      bin/millennium_quiz eval "MillenniumQuiz.Release.seed()"
      bin/millennium_quiz eval "MillenniumQuiz.Release.refresh_cards()"
      bin/millennium_quiz eval "MillenniumQuiz.Release.refresh_card_names()"
      bin/millennium_quiz eval 'MillenniumQuiz.Release.export_quiz("quiz-backup.json")'
      bin/millennium_quiz eval 'MillenniumQuiz.Release.import_quiz("quiz-backup.json")'
  """
  require Logger

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

  @doc """
  Content for `bin/layout-test`: a format with questions of 4, 3 and 1 cards,
  and four cards that exist nowhere else. For CI and local servers only: it
  refuses to run unless `LAYOUT_FIXTURE=1` is set, so it cannot be run on the
  live database by accident (the Smoke workflow sets it).
  """
  def seed_layout_fixture do
    if System.get_env("LAYOUT_FIXTURE") == "1" do
      with_repo(fn ->
        Code.eval_file(Application.app_dir(@app, "priv/repo/layout_fixture.exs"))
      end)
    else
      IO.puts("Not seeding the layout fixture: set LAYOUT_FIXTURE=1 (CI and local servers only).")
    end
  end

  @doc """
  Fills the list of all TCG card names (`MillenniumQuiz.Cards.CardNames`) from
  YGOPRODeck: about 27 requests, one per release year, paced by a gate. The
  running application refreshes the list by itself (`CardNames.Refresher`);
  this is for a host where it cannot, or to fill the list at once.

  This VM is not the application, so it has a gate of its own, and the
  application's gate does not know its requests. To stay under the API's cap
  (20 a second) together, the gate here gets half of the default budget
  (4 a second): 8 in the application plus 4 here.
  """
  def refresh_card_names do
    {:ok, _} = Application.ensure_all_started(:req)

    with_repo(fn ->
      :ok = start_gate()
      IO.puts(card_names_report(MillenniumQuiz.Cards.CardNames.refresh()))
    end)
  end

  @doc false
  def start_gate do
    case MillenniumQuiz.Cards.Sources.YGOPRODeck.Gate.start_link(rate: 4, burst: 4) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  @doc "The line that says how `CardNames.refresh/1` went."
  def card_names_report({:ok, count}), do: "Card names: #{count} written"

  def card_names_report({:error, reason, count}),
    do:
      "Card names: stopped after #{count} names fetched: #{inspect(reason)}. " <>
        "Nothing was written. Run it again."

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

  @doc """
  Runs all pending migrations on a repo that is already started (used by
  `MillenniumQuiz.MigrateOnBoot`); does not start or stop the repo.
  """
  def migrate_running(repo) do
    Ecto.Migrator.run(repo, :up, all: true)
  end

  @doc """
  Creates the first admin from ADMIN_USERNAME / ADMIN_PASSWORD when the users
  table is still empty. With ADMIN_PASSWORD_RESET=true it instead sets that
  password on the existing user ADMIN_USERNAME (and logs them out everywhere),
  for hosts without a shell when the password is lost. Needs a started repo.
  Runs as part of `migrate`.
  """
  def bootstrap_admin_if_empty do
    username = System.get_env("ADMIN_USERNAME")
    password = System.get_env("ADMIN_PASSWORD")

    cond do
      !(username && password) ->
        :ok

      MillenniumQuiz.Repo.aggregate(MillenniumQuiz.Accounts.User, :count) == 0 ->
        do_create_admin(username, password)

      System.get_env("ADMIN_PASSWORD_RESET") == "true" ->
        Logger.warning("ADMIN_PASSWORD_RESET is set: unset it once you can log in")
        do_reset_password(username, password)

      true ->
        :ok
    end

    :ok
  end

  defp do_reset_password(username, password) do
    alias MillenniumQuiz.Accounts
    alias MillenniumQuiz.Accounts.{User, UserToken}

    with %User{} = user <- Accounts.get_user_by_username(username),
         false <- User.valid_password?(user, password),
         {:ok, _} <-
           Ecto.Multi.new()
           |> Ecto.Multi.update(:user, User.password_changeset(user, %{password: password}))
           |> Ecto.Multi.delete_all(
             :tokens,
             UserToken.by_user_and_contexts_query(user, ["session"])
           )
           |> MillenniumQuiz.Repo.transaction() do
      IO.puts("Reset the password of #{user.username}")
    else
      true ->
        IO.puts("The password of #{inspect(username)} is already the one in ADMIN_PASSWORD")

      nil ->
        IO.puts("Could not reset the password: no user #{inspect(username)}")

      {:error, _, changeset, _} ->
        IO.puts("Could not reset the password: #{inspect(changeset.errors)}")
    end
  end

  defp maybe_bootstrap_admin do
    if System.get_env("ADMIN_USERNAME") && System.get_env("ADMIN_PASSWORD") do
      with_repo(&bootstrap_admin_if_empty/0)
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
