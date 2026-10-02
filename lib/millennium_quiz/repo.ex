defmodule MillenniumQuiz.Repo do
  use Ecto.Repo,
    otp_app: :millennium_quiz,
    adapter: Ecto.Adapters.Postgres
end
