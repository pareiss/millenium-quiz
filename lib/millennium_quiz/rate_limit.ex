defmodule MillenniumQuiz.RateLimit do
  @moduledoc """
  Fixed-window rate limiting (Hammer, ETS backend; per node, not shared in a
  cluster).

  `check/3` is the primitive. The named rules below are what the web layer
  uses, so every limit is in one place and can be changed with

      config :millennium_quiz, MillenniumQuiz.RateLimit,
        enabled: true,
        limits: [login_ip: {20, :timer.minutes(5)}]

  where a limit is `{max_hits, window_ms}`. With `enabled: false` every check
  passes (the test suite does this in `test/test_helper.exs`).
  """

  @defaults %{
    login_ip: {10, :timer.minutes(5)},
    login_user: {5, :timer.minutes(5)},
    password_user: {5, :timer.minutes(15)},
    email_game: {3, :timer.hours(1)},
    email_ip: {10, :timer.hours(1)},
    create_ip: {20, :timer.hours(1)},
    # Suggested questions (`MillenniumQuizWeb.SuggestLive`).
    submit_ip: {5, :timer.hours(1)},
    # Caps that do not depend on the client address (addresses can be rotated).
    # Deliberately none for logins: it would let an attacker lock the admin out.
    email_global: {60, :timer.hours(1)},
    create_global: {300, :timer.hours(1)},
    # Name lookups at YGOPRODeck while a player types (`SuggestLive`).
    suggest_remote_ip: {30, :timer.minutes(1)},
    submit_global: {100, :timer.hours(1)},
    # All events of one LiveView socket (`MillenniumQuizWeb.EventLimit`).
    socket_events: {120, :timer.seconds(10)},
    # Cache misses for resized card artwork per client; over it, the original
    # image is served (`MillenniumQuizWeb.CardArtworkController`).
    artwork_resize_ip: {120, :timer.minutes(1)}
  }

  defmodule Backend do
    @moduledoc false
    use Hammer, backend: :ets
  end

  @doc false
  def child_spec(_opts) do
    Backend.child_spec(clean_period: :timer.minutes(1))
  end

  @doc """
  Counts one hit for `bucket_key` and returns `:ok` while it is within `limit`
  hits per `window_ms`, otherwise `{:error, retry_after_ms}`.
  """
  def check(bucket_key, limit, window_ms) do
    if enabled?() do
      case Backend.hit(bucket_key, window_ms, limit) do
        {:allow, _count} -> :ok
        {:deny, retry_after_ms} -> {:error, max(retry_after_ms, 1)}
      end
    else
      :ok
    end
  end

  @doc "Like `check/3` for a named rule (see the module doc) and an identifier."
  def check_rule(rule, id) when is_map_key(@defaults, rule) do
    {limit, window_ms} = limit(rule)
    check({rule, id}, limit, window_ms)
  end

  @doc """
  Like `check_rule/2` but counts nothing: `:ok` while the current window still
  has room, `{:error, window_ms}` (the whole window, as the rest isn't known)
  otherwise. For checks whose hits are counted somewhere else or only on
  failure.
  """
  def peek(rule, id) when is_map_key(@defaults, rule) do
    {limit, window_ms} = limit(rule)

    if enabled?() and Backend.get({rule, id}, window_ms) >= limit,
      do: {:error, window_ms},
      else: :ok
  end

  @doc "The `{max_hits, window_ms}` of a rule, with configuration applied."
  def limit(rule) when is_map_key(@defaults, rule) do
    config = Application.get_env(:millennium_quiz, __MODULE__, [])
    overrides = config |> Keyword.get(:limits, %{}) |> Map.new()
    Map.get(overrides, rule, Map.fetch!(@defaults, rule))
  end

  @doc "Checks several `{rule, id}` pairs; stops at the first denial."
  def check_all(pairs) do
    Enum.reduce_while(pairs, :ok, fn {rule, id}, :ok ->
      case check_rule(rule, id) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc "Waiting time for people: \"about 3 minutes\"."
  def describe_wait(retry_after_ms) do
    minutes = max(div(retry_after_ms + 59_999, 60_000), 1)
    if minutes == 1, do: "about a minute", else: "about #{minutes} minutes"
  end

  @doc "Seconds for a `Retry-After` header."
  def retry_after_seconds(retry_after_ms), do: max(div(retry_after_ms + 999, 1000), 1)

  defp enabled? do
    :millennium_quiz |> Application.get_env(__MODULE__, []) |> Keyword.get(:enabled, true)
  end
end
