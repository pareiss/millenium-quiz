defmodule MillenniumQuiz.Cards.Sources.HTTP do
  @moduledoc false
  # Shared Req setup for the card sources. Tests route every source through
  # one stub: `config :millennium_quiz, MillenniumQuiz.Cards,
  # req_options: [plug: {Req.Test, MillenniumQuiz.Cards}]`.

  @user_agent "MillenniumQuiz/0.1 (+https://github.com/pareiss/millenium-quiz)"

  def new(base_url) do
    options = Application.get_env(:millennium_quiz, MillenniumQuiz.Cards, [])[:req_options] || []
    Req.new([base_url: base_url, user_agent: @user_agent, max_retries: 2] ++ options)
  end
end
