defmodule MillenniumQuiz.ReleaseImportReportTest do
  use ExUnit.Case, async: true

  alias MillenniumQuiz.Release

  test "describes an error" do
    assert ["Import failed: nope"] = Release.import_report({:error, "nope"})
  end

  test "describes a summary with skipped, failed and warnings" do
    summary = %{
      formats_created: 1,
      formats_skipped: ["Old"],
      formats_failed: [{"Broken", "topics must have 2"}],
      topics: 2,
      questions: 3,
      cards_linked: 4,
      cards_missing: 1,
      warnings: ["card X missing"]
    }

    lines = Release.import_report({:ok, summary})
    assert "Skipped: Old" in lines
    assert "Failed: Broken: topics must have 2" in lines
    assert "Warning: card X missing" in lines
    assert Enum.any?(lines, &(&1 =~ "4 linked, 1 missing"))
  end
end
