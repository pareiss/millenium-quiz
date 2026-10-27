defmodule MillenniumQuiz.ReleaseCardNamesTest do
  use ExUnit.Case, async: true

  alias MillenniumQuiz.Release

  test "the report says how many names were written, or where it stopped" do
    assert Release.card_names_report({:ok, 14_137}) == "Card names: 14137 written"

    assert Release.card_names_report({:error, {:http, 429}, 3000}) =~
             "stopped after 3000 written: {:http, 429}. Run it again."
  end

  test "starting the gate twice is fine (the application's own may be running)" do
    assert :ok = Release.start_gate()
    assert :ok = Release.start_gate()
  end
end
