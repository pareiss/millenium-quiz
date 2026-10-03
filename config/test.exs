import Config

# Only in tests: make hashing passwords fast
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :millennium_quiz, MillenniumQuiz.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "millennium_quiz_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :millennium_quiz, MillenniumQuizWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "LtlEC4bX2digtR+FKw7Xe8yVVekoKT5lCRZNj9MTXTR+sHAz7Y4g0qObgCx/puCg",
  server: false

# In test we don't send emails
config :millennium_quiz, MillenniumQuiz.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Card sources (YGOPRODeck, YAML Yugi, Yugipedia) never hit the network in
# tests; see MillenniumQuiz.CardSourcesStub.
config :millennium_quiz, MillenniumQuiz.Cards,
  req_options: [plug: {Req.Test, MillenniumQuiz.Cards}],
  refresh_pause_ms: 0
