defmodule MillenniumQuizWeb.NoBrowserDialogsTest do
  @moduledoc """
  Confirmations use the in-app `confirm_dialog/1`, never the browser's
  pop-ups: `data-confirm` (Phoenix turns it into `window.confirm`),
  `confirm()`, `alert()` or `prompt()`.
  """
  use ExUnit.Case, async: true

  @pattern ~r/data-confirm\s*=|\b(?:window\.)?(?:confirm|alert|prompt)\s*\(/

  test "no browser pop-ups in the app's code" do
    files =
      Path.wildcard("lib/**/*.{ex,exs,heex}") ++
        Path.wildcard("assets/js/**/*.{js,ts}", match_dot: false)

    offenders =
      for file <- files,
          not String.contains?(file, "/vendor/"),
          {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          Regex.match?(@pattern, line),
          do: "#{file}:#{number}: #{String.trim(line)}"

    assert offenders == [], "use <.confirm_dialog> instead:\n" <> Enum.join(offenders, "\n")
  end
end
