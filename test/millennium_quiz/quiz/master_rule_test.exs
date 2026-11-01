defmodule MillenniumQuiz.Quiz.MasterRuleTest do
  use ExUnit.Case, async: true

  alias MillenniumQuiz.Quiz.MasterRule

  test "for_date/1 at the edges of every era" do
    assert MasterRule.for_date(~D[2005-04-01]) == :mr1_2
    assert MasterRule.for_date(~D[2010-04-24]) == :mr1_2
    assert MasterRule.for_date(~D[2011-09-01]) == :mr1_2
    assert MasterRule.for_date(~D[2013-12-31]) == :mr1_2
    assert MasterRule.for_date(~D[2014-01-01]) == :mr3
    assert MasterRule.for_date(~D[2017-03-31]) == :mr3
    assert MasterRule.for_date(~D[2017-04-01]) == :mr4
    assert MasterRule.for_date(~D[2026-11-01]) == :mr4
  end

  test "a format without a date has the newest rule" do
    assert MasterRule.for_date(nil) == :mr4
  end

  test "rules/0 is the one place with the dates, oldest first" do
    assert [:mr1_2, :mr3, :mr4] = Enum.map(MasterRule.rules(), & &1.key)
    assert [nil, ~D[2014-01-01], ~D[2017-04-01]] = Enum.map(MasterRule.rules(), & &1.starts_on)
  end

  test "allows?/2 by key and by date" do
    refute MasterRule.allows?(:mr1_2, :emz)
    refute MasterRule.allows?(:mr3, :emz)
    assert MasterRule.allows?(:mr4, :emz)
    refute MasterRule.allows?(:mr1_2, :pendulum_scales)
    assert MasterRule.allows?(:mr3, :pendulum_scales)
    assert MasterRule.allows?(~D[2017-04-01], :pendulum_scales)
    refute MasterRule.allows?(~D[2013-12-31], :pendulum_scales)
    refute MasterRule.allows?(~D[2005-04-01], :emz)
  end

  test "overlay units follow the Xyz date, not the rule" do
    refute MasterRule.allows?(~D[2005-04-01], :overlay_units)
    refute MasterRule.allows?(~D[2010-04-24], :overlay_units)
    assert MasterRule.allows?(~D[2011-09-01], :overlay_units)
    assert MasterRule.allows?(~D[2011-06-01], :overlay_units)
    # without a date the answer is lenient
    assert MasterRule.allows?(:mr1_2, :overlay_units)
    assert MasterRule.allows?(nil, :overlay_units)
  end

  test "an unknown rule key raises a clear error" do
    assert_raise ArgumentError, ~r/unknown Master Rule :mr5/, fn -> MasterRule.get(:mr5) end
  end
end
