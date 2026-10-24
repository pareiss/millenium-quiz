defmodule MillenniumQuiz.RateLimitTest do
  use ExUnit.Case

  alias MillenniumQuiz.RateLimit

  setup do
    previous = Application.get_env(:millennium_quiz, RateLimit)
    Application.put_env(:millennium_quiz, RateLimit, enabled: true)
    on_exit(fn -> Application.put_env(:millennium_quiz, RateLimit, previous) end)
    :ok
  end

  defp key, do: {:test, System.unique_integer([:positive])}

  test "allows up to the limit, then says how long to wait" do
    key = key()
    assert :ok = RateLimit.check(key, 2, 60_000)
    assert :ok = RateLimit.check(key, 2, 60_000)
    assert {:error, retry_after} = RateLimit.check(key, 2, 60_000)
    assert retry_after in 1..60_000
  end

  test "keys are counted separately" do
    assert :ok = RateLimit.check(key(), 1, 60_000)
    assert :ok = RateLimit.check(key(), 1, 60_000)
  end

  test "the window ends" do
    key = key()
    assert :ok = RateLimit.check(key, 1, 50)
    assert {:error, retry_after} = RateLimit.check(key, 1, 50)
    Process.send_after(self(), :window_over, retry_after + 20)
    assert_receive :window_over, 1000
    assert :ok = RateLimit.check(key, 1, 50)
  end

  test "rules use their configured limits" do
    Application.put_env(:millennium_quiz, RateLimit,
      enabled: true,
      limits: %{create_ip: {1, 60_000}}
    )

    id = "rule-#{System.unique_integer([:positive])}"
    assert RateLimit.limit(:create_ip) == {1, 60_000}
    assert RateLimit.limit(:login_ip) == {10, 300_000}
    assert :ok = RateLimit.check_rule(:create_ip, id)
    assert {:error, _} = RateLimit.check_rule(:create_ip, id)
  end

  test "check_all stops at the first denial" do
    Application.put_env(:millennium_quiz, RateLimit,
      enabled: true,
      limits: %{email_game: {1, 60_000}}
    )

    id = "g-#{System.unique_integer([:positive])}"
    assert :ok = RateLimit.check_all(email_game: id)
    assert {:error, _} = RateLimit.check_all(email_game: id, email_ip: "never-counted")
    assert :ok = RateLimit.check_rule(:email_ip, "never-counted")
  end

  test "disabled limits let everything pass" do
    Application.put_env(:millennium_quiz, RateLimit, enabled: false)
    key = key()
    for _ <- 1..5, do: assert(:ok = RateLimit.check(key, 1, 60_000))
  end

  test "wait times are readable" do
    assert RateLimit.describe_wait(1) == "about a minute"
    assert RateLimit.describe_wait(150_000) == "about 3 minutes"
    assert RateLimit.retry_after_seconds(1500) == 2
  end
end
