ExUnit.start()

# Rate limits are off in the suite; the tests of the limits switch them on.
Application.put_env(:millennium_quiz, MillenniumQuiz.RateLimit, enabled: false)

Ecto.Adapters.SQL.Sandbox.mode(MillenniumQuiz.Repo, :manual)
