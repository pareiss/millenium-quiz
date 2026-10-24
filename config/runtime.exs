import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/millennium_quiz start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :millennium_quiz, MillenniumQuizWeb.Endpoint, server: true
end

config :millennium_quiz, MillenniumQuizWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :millennium_quiz, MillenniumQuizWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Gettext translations
        ~r"priv/gettext/.*\.po$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/millennium_quiz_web/router\.ex$",
        ~r"lib/millennium_quiz_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # DATABASE_SSL=true: TLS to a database that is reached over a network,
  # verified against the system's CA certificates
  db_ssl =
    if System.get_env("DATABASE_SSL") in ~w(true 1) do
      host = URI.parse(database_url).host || "localhost"

      [
        ssl: [
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          server_name_indication: String.to_charlist(host)
        ]
      ]
    else
      []
    end

  config :millennium_quiz, MillenniumQuiz.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  config :millennium_quiz, MillenniumQuiz.Repo, db_ssl

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  # Behind a proxy the client's address is in X-Forwarded-For: how many proxies
  # of the platform append to it (0 = none, use the connection's address).
  # Used by the rate limits; a wrong value lets clients pick their own address.
  config :millennium_quiz,
         :trusted_proxy_hops,
         String.to_integer(System.get_env("TRUSTED_PROXY_HOPS", "0"))

  # Platforms without a shell (Gigalixir's free tier): run the migrations, and
  # create the first admin from ADMIN_*, when the app starts.
  config :millennium_quiz, :migrate_on_boot, System.get_env("MIGRATE_ON_BOOT") in ~w(true 1)

  # A cap on stored games (a small database has a row limit); empty = no cap.
  game_limit =
    case System.get_env("GAME_LIMIT") do
      nil -> nil
      "" -> nil
      n -> String.to_integer(n)
    end

  config :millennium_quiz, :game_limit, game_limit

  # Games nobody touched for this many days are deleted (finished ones after
  # GAME_EXPIRY_FINISHED_DAYS).
  config :millennium_quiz,
         :game_expiry_days,
         String.to_integer(System.get_env("GAME_EXPIRY_DAYS", "30"))

  config :millennium_quiz,
         :game_expiry_finished_days,
         String.to_integer(System.get_env("GAME_EXPIRY_FINISHED_DAYS", "7"))

  config :millennium_quiz, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # The public URL is used for resume links (emails, QR codes) and for the
  # websocket origin check. Use PHX_SCHEME=http / PHX_URL_PORT=80 without TLS.
  scheme = System.get_env("PHX_SCHEME", "https")
  url_port = String.to_integer(System.get_env("PHX_URL_PORT", "443"))

  # https deployments: redirect to https and use secure cookies; a plain-http
  # one (PHX_SCHEME=http, e.g. the local k3s) can do neither
  config :millennium_quiz, force_https: scheme == "https", secure_cookies: scheme == "https"

  # Websocket origins: the public host, and further ones when the platform also
  # serves the app under its own address (PHX_ALLOWED_ORIGINS, comma separated
  # hosts such as myapp.gigalixirapp.com).
  extra_origins =
    "PHX_ALLOWED_ORIGINS"
    |> System.get_env("")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)

  check_origin = Enum.map([host | extra_origins], &"//#{&1}")

  config :millennium_quiz, MillenniumQuizWeb.Endpoint,
    check_origin: check_origin,
    url: [host: host, port: url_port, scheme: scheme],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :millennium_quiz, MillenniumQuizWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :millennium_quiz, MillenniumQuizWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Mailer for "email me the resume link". Without SMTP_HOST mails are only
  # logged (at debug level: the recipient is personal data), so the app also
  # works without any mail setup.
  #
  # SMTP_SECURITY: "starttls" (default, port 587), "ssl" (implicit TLS, port
  # 465) or "none" (only for a relay on a trusted private network). With TLS the
  # relay's certificate is verified, and the connection fails rather than
  # falling back to plain text, so the credentials never travel unprotected.
  if smtp_host = System.get_env("SMTP_HOST") do
    security = System.get_env("SMTP_SECURITY", "starttls")

    unless security in ~w(starttls ssl none) do
      raise "SMTP_SECURITY must be starttls, ssl or none, got: #{security}"
    end

    tls_options = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(smtp_host),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)],
      depth: 3
    ]

    default_port = if security == "ssl", do: "465", else: "587"

    # credentials: both or neither (a relay that needs none is allowed)
    username = System.get_env("SMTP_USERNAME")
    password = System.get_env("SMTP_PASSWORD")

    if is_nil(username) != is_nil(password) do
      raise "SMTP_USERNAME and SMTP_PASSWORD must be set together"
    end

    auth = if username, do: :always, else: :never

    tls_config =
      case security do
        "starttls" -> [tls: :always, auth: auth, tls_options: tls_options]
        "ssl" -> [ssl: true, tls: :never, auth: auth, sockopts: tls_options]
        "none" -> [tls: :never, auth: if(username, do: :if_available, else: :never)]
      end

    config :millennium_quiz,
           MillenniumQuiz.Mailer,
           [
             adapter: Swoosh.Adapters.SMTP,
             relay: smtp_host,
             port: String.to_integer(System.get_env("SMTP_PORT", default_port)),
             username: username,
             password: password
           ] ++ tls_config
  else
    config :millennium_quiz, MillenniumQuiz.Mailer, adapter: Swoosh.Adapters.Logger, level: :debug
  end

  if mail_from = System.get_env("MAIL_FROM") do
    config :millennium_quiz, :mail_from, mail_from
  end
end
