defmodule MillenniumQuiz.ReleaseCardNamesTest do
  use ExUnit.Case, async: true

  alias MillenniumQuiz.Release

  test "the report says how many names were written, or where it stopped and that nothing was" do
    assert Release.card_names_report({:ok, 14_137}) == "Card names: 14137 written"

    report = Release.card_names_report({:error, {:http, 429}, 3000})
    assert report =~ "stopped after 3000 names fetched: {:http, 429}"
    assert report =~ "Nothing was written. Run it again."
  end

  test "starting the gate twice is fine (the application's own may be running)" do
    assert :ok = Release.start_gate()
    assert :ok = Release.start_gate()
  end
end
