defmodule Mix.Tasks.Avatars.Adopt do
  @shortdoc "Copies the built-in profile-picture sets into the table"
  @moduledoc """
  Makes the built-in sets of Edison, Goat and Tengu the formats' own profile
  pictures (`MillenniumQuiz.Quiz.AvatarSets`): missing cards are fetched one at a
  time, formats that have picture cards already are left alone.

      mix avatars.adopt
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    MillenniumQuiz.Release.start_gate()

    MillenniumQuiz.Quiz.AvatarSets.adopt()
    |> MillenniumQuiz.Release.adopt_report()
    |> Enum.each(&Mix.shell().info/1)
  end
end
