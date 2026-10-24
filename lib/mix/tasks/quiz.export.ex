defmodule Mix.Tasks.Quiz.Export do
  @shortdoc "Writes a backup of the quiz content to a JSON file"
  @moduledoc """
  Writes the formats, topics, questions, choices and card links to a file.

      mix quiz.export [path]

  The default path is `quiz-backup.json`. Restore with `mix quiz.import`.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    path = List.first(args) || "quiz-backup.json"
    File.write!(path, MillenniumQuiz.Quiz.Export.to_json())
    Mix.shell().info("Wrote the quiz backup to #{path}")
  end
end
