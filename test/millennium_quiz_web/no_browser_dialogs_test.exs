defmodule MillenniumQuizWeb.NoBrowserDialogsTest do
  @moduledoc """
  Confirmations use the in-app `confirm_dialog/1`, never the browser's
  pop-ups: `data-confirm` (Phoenix turns it into `window.confirm`),
  `confirm()`, `alert()` or `prompt()`.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  # JavaScript: any call of the browser's dialog functions.
  @js ~r/(?<![\w.$])(?:window\.)?(?:confirm|alert|prompt)\s*\(/
  # Elixir and templates: data-confirm attributes, and window.* calls in
  # colocated hooks. A plain Elixir function named e.g. confirm/1 is fine.
  @elixir ~r/data-confirm\s*=|window\.(?:confirm|alert|prompt)\s*\(/

  test "no browser pop-ups in the app's code" do
    offenders =
      offenders(["lib/**/*.{ex,exs,heex}"], @elixir) ++
        offenders(["assets/js/**/*.{js,ts}"], @js)

    assert offenders == [], "use <.confirm_dialog> instead:\n" <> Enum.join(offenders, "\n")
  end

  test "the patterns catch what they should, and only that" do
    for line <- ["confirm('Sure?')", "if (window.confirm(msg))", "alert(1)", "prompt (x)"],
        do: assert(Regex.match?(@js, line), line)

    for line <- ["el.confirm(x)", "reconfirm(x)", "const confirmed = true"],
        do: refute(Regex.match?(@js, line), line)

    for line <- [~s(data-confirm="Sure?"), "data-confirm={msg}", "window.alert(x)"],
        do: assert(Regex.match?(@elixir, line), line)

    for line <- ["def confirm(user)", "Accounts.confirm(token)", "confirm_dialog("],
        do: refute(Regex.match?(@elixir, line), line)
  end

  defp offenders(globs, pattern) do
    for glob <- globs,
        file <- Path.wildcard(Path.join(@root, glob)),
        not String.contains?(file, "/vendor/"),
        {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
        Regex.match?(pattern, line),
        do: "#{Path.relative_to(file, @root)}:#{number}: #{String.trim(line)}"
  end
end
