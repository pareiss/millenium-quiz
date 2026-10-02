defmodule MillenniumQuiz.Release do
  @moduledoc """
  Tasks run inside the release, where Mix is not available:

      bin/millennium_quiz eval "MillenniumQuiz.Release.migrate()"
      bin/millennium_quiz eval 'MillenniumQuiz.Release.create_admin("name", "a long password")'
      bin/millennium_quiz eval "MillenniumQuiz.Release.seed()"
      bin/millennium_quiz eval "MillenniumQuiz.Release.refresh_cards()"
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
