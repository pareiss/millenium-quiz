defmodule Mix.Tasks.Quiz.Import do
  @shortdoc "Restores a quiz backup file"
  @moduledoc """
  Restores a file made by `mix quiz.export`.

      mix quiz.import path

  Formats whose name exists are skipped. Missing cards are fetched from the
  remote sources, one at a time.
  """
  use Mix.Task

  @impl Mix.Task
  def run([path]) do
    Mix.Task.run("app.start")

    case File.read(path) do
      {:ok, json} ->
        json
        |> MillenniumQuiz.Quiz.Import.run()
        |> MillenniumQuiz.Release.import_report()
        |> Enum.each(&Mix.shell().info/1)

      {:error, reason} ->
        Mix.raise("Could not read #{path}: #{:file.format_error(reason)}")
    end
  end

  def run(_), do: Mix.raise("Usage: mix quiz.import path")
end
