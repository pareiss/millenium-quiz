defmodule MillenniumQuiz.MigrateOnBoot do
  @moduledoc """
  Optionally runs the migrations (and bootstraps the first admin) while the
  application starts, for hosts without a shell to run `bin/migrate`.

  It sits in the supervision tree right after the repo, so the endpoint and
  everything else that touches the tables starts afterwards. It enables itself
  with `config :millennium_quiz, :migrate_on_boot, true` (env `MIGRATE_ON_BOOT`
  in `config/runtime.exs`). `start_link/1` works synchronously and returns
  `:ignore`; a failing migration raises, which stops the application with the
  error. It uses the already running repo and never stops it. Only one pool
  connection is held at a time (the migrator's lock), so a pool of 2 is enough.
  """

  alias MillenniumQuiz.Release

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}
  end

  def start_link(_opts) do
    run(MillenniumQuiz.Repo, Application.get_env(:millennium_quiz, :migrate_on_boot, false))
    :ignore
  end

  @doc "Migrates `repo` and bootstraps the admin when `enabled?` is true."
  def run(repo, true) do
    {:ok, _} = Application.ensure_all_started(:bcrypt_elixir)

    try do
      Release.migrate_running(repo)
      Release.bootstrap_admin_if_empty()
    rescue
      error ->
        reraise "Migration on boot failed, refusing to start: " <> Exception.message(error),
                __STACKTRACE__
    end

    :ok
  end

  def run(_repo, _enabled?), do: :noop
end
