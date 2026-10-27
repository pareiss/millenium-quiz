defmodule MillenniumQuiz.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MillenniumQuizWeb.Telemetry,
      MillenniumQuiz.Repo,
      # Runs migrations before anything else touches the tables (opt-in).
      MillenniumQuiz.MigrateOnBoot,
      {DNSCluster, query: Application.get_env(:millennium_quiz, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MillenniumQuiz.PubSub},
      MillenniumQuiz.Cards.ArtworkCache,
      MillenniumQuiz.Cards.Sources.YGOPRODeck.Gate,
      MillenniumQuiz.RateLimit,
      {Task.Supervisor, name: MillenniumQuiz.TaskSupervisor},
      MillenniumQuiz.Cards.CardNames.Refresher,
      {Registry, keys: :unique, name: MillenniumQuiz.Games.Registry},
      {DynamicSupervisor, name: MillenniumQuiz.Games.Supervisor, strategy: :one_for_one},
      # Start to serve requests, typically the last entry
      MillenniumQuizWeb.Endpoint
    ]

    # Old games are only deleted where :game_expiry_days is configured (prod).
    children = children ++ expiry_children()

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MillenniumQuiz.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp expiry_children do
    if Application.get_env(:millennium_quiz, :game_expiry_days),
      do: [MillenniumQuiz.Games.Expiry],
      else: []
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MillenniumQuizWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
