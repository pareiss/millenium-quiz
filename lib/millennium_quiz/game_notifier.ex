defmodule MillenniumQuiz.GameNotifier do
  @moduledoc "Emails sent to players. The address is used once and not stored."
  import Swoosh.Email

  alias MillenniumQuiz.Mailer

  def deliver_resume_link(recipient, url, %MillenniumQuiz.Game{} = game) do
    names = Enum.map_join(game.players, ", ", & &1.name)

    email =
      new()
      |> to(recipient)
      |> from({"Millennium Quiz", Application.get_env(:millennium_quiz, :mail_from)})
      |> subject("Continue your Millennium Quiz game: #{game.category_name}")
      |> text_body("""
      Your game "#{game.category_name}" (#{names}) is paused at question #{game.round} of #{MillenniumQuiz.Game.total_rounds(game)}.

      Continue on any device:
      #{url}
      """)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
