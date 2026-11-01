defmodule MillenniumQuiz.Quiz.MasterRulesTest do
  use MillenniumQuiz.DataCase, async: false

  import Ecto.Query
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{CardSourcesStub, Repo}
  alias MillenniumQuiz.Quiz.{Export, Format, Import, MasterRule, MasterRules}
  alias MillenniumQuiz.Quiz.{MasterRuleFeature, MasterRuleSetting}

  @ok %{"mr3" => "2014-01-01", "mr4" => "2017-04-01", "xyz" => "2011-06-01"}

  defp put(overrides), do: Map.merge(@ok, overrides)

  defp row(key), do: from(r in MasterRuleSetting, where: r.key == ^key)

  test "the migration seeded the defaults" do
    assert Repo.aggregate(MasterRuleSetting, :count) == 3
    assert Repo.aggregate(MasterRuleFeature, :count) == 1
    assert MasterRules.dates() == MasterRules.default_dates()

    assert MasterRules.default_dates() == %{
             mr3: ~D[2014-01-01],
             mr4: ~D[2017-04-01],
             xyz: ~D[2011-06-01]
           }

    [r1, r3, r4] = MasterRule.rules()
    assert {r1.key, r1.starts_on, r1.emz, r1.pendulum_scales} == {:mr1_2, nil, false, false}
    assert {r3.key, r3.emz, r3.pendulum_scales} == {:mr3, false, true}
    assert {r4.key, r4.emz, r4.pendulum_scales} == {:mr4, true, true}
  end

  describe "validate/1" do
    test "accepts valid dates, as strings or dates" do
      assert {:ok, %{mr3: ~D[2014-01-01]}} = MasterRules.validate(@ok)

      assert {:ok, %{mr4: ~D[2017-04-01]}} =
               MasterRules.validate(%{
                 mr3: ~D[2014-01-01],
                 mr4: ~D[2017-04-01],
                 xyz: ~D[2011-06-01]
               })
    end

    test "Master Rule 3 must start before Master Rule 4" do
      assert {:error, %{mr4: msg}} = MasterRules.validate(put(%{"mr4" => "2014-01-01"}))
      assert msg =~ "must be after the start of Master Rule 3 (2014-01-01)"
      assert {:error, %{mr4: _}} = MasterRules.validate(put(%{"mr4" => "2013-05-05"}))
      assert {:ok, _} = MasterRules.validate(put(%{"mr4" => "2014-01-02"}))
    end

    test "a date that is missing or not a date" do
      assert {:error, %{mr3: "must be a date like 2014-01-01."}} =
               MasterRules.validate(put(%{"mr3" => "soon"}))

      assert {:error, %{mr3: "must be a date like 2014-01-01."}} =
               MasterRules.validate(put(%{"mr3" => "2014-13-01"}))

      assert {:error, %{xyz: "is required" <> _}} = MasterRules.validate(Map.delete(@ok, "xyz"))
      assert {:error, %{xyz: "must be a date" <> _}} = MasterRules.validate(put(%{"xyz" => ""}))
      assert {:error, errors} = MasterRules.validate(%{})
      assert errors |> Map.keys() |> Enum.sort() == [:mr3, :mr4, :xyz]
    end

    test "dates must be plausible" do
      assert {:error, %{mr3: "is not plausible" <> _}} =
               MasterRules.validate(put(%{"mr3" => "1999-01-01"}))

      assert {:error, %{mr4: "is not plausible" <> _}} =
               MasterRules.validate(put(%{"mr4" => "2099-01-01"}))

      assert {:error, %{xyz: "is not plausible" <> _}} =
               MasterRules.validate(put(%{"xyz" => "2003-01-01"}))

      assert {:error, %{xyz: "is not plausible" <> _}} =
               MasterRules.validate(put(%{"xyz" => "2020-01-01"}))

      assert {:ok, _} = MasterRules.validate(put(%{"xyz" => "2008-12-04"}))
    end
  end

  describe "save/1 and reset/0" do
    test "a saved date is what MasterRule answers" do
      assert {:ok, _} = MasterRules.save(put(%{"mr3" => "2013-06-01", "mr4" => "2017-06-01"}))

      assert MasterRule.for_date(~D[2013-06-01]) == :mr3
      assert MasterRule.for_date(~D[2013-05-31]) == :mr1_2
      assert MasterRule.for_date(~D[2017-05-31]) == :mr3
      assert MasterRule.for_date(~D[2017-06-01]) == :mr4
      assert [nil, ~D[2013-06-01], ~D[2017-06-01]] = Enum.map(MasterRule.rules(), & &1.starts_on)
    end

    test "the Xyz date is editable and read by allows?/2" do
      refute MasterRule.allows?(~D[2011-05-31], :overlay_units)
      assert {:ok, _} = MasterRules.save(put(%{"xyz" => "2012-01-01"}))
      refute MasterRule.allows?(~D[2011-12-31], :overlay_units)
      assert MasterRule.allows?(~D[2012-01-01], :overlay_units)
    end

    test "an invalid save changes nothing" do
      assert {:error, _} = MasterRules.save(put(%{"mr3" => "2018-01-01"}))
      assert MasterRules.dates() == MasterRules.default_dates()
    end

    test "save keeps what each rule has" do
      assert {:ok, _} = MasterRules.save(put(%{"mr3" => "2013-06-01"}))
      assert Repo.one!(row("mr4")).emz
      refute Repo.one!(row("mr3")).emz
      assert Repo.one!(row("mr1_2")).starts_on == nil
    end

    test "reset puts the defaults back" do
      {:ok, _} = MasterRules.save(put(%{"mr3" => "2013-06-01", "xyz" => "2012-01-01"}))
      assert {:ok, _} = MasterRules.reset()
      assert MasterRules.dates() == MasterRules.default_dates()
      assert MasterRule.for_date(~D[2013-12-31]) == :mr1_2
    end
  end

  describe "fallbacks" do
    test "empty tables give the built-in defaults" do
      Repo.delete_all(MasterRuleSetting)
      Repo.delete_all(MasterRuleFeature)

      assert MasterRules.dates() == MasterRules.default_dates()
      assert MasterRule.for_date(~D[2015-01-01]) == :mr3
      assert MasterRule.allows?(:mr4, :emz)
    end

    test "a missing row is filled from the defaults" do
      Repo.delete_all(MasterRuleFeature)
      Repo.delete_all(row("mr3"))
      assert MasterRules.dates() == MasterRules.default_dates()
    end

    test "saving into empty tables creates the rows" do
      Repo.delete_all(MasterRuleSetting)
      Repo.delete_all(MasterRuleFeature)
      assert {:ok, _} = MasterRules.save(put(%{"mr3" => "2013-06-01"}))
      assert Repo.aggregate(MasterRuleSetting, :count) == 3
      assert MasterRules.dates().mr3 == ~D[2013-06-01]
    end

    test "a database that cannot be read gives the defaults, not a crash" do
      {:ok, _} = MasterRules.save(put(%{"mr3" => "2013-06-01"}))

      # manual mode: a process that was not allowed the connection gets an
      # ownership error from the repo, as it would get a connection error
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)

      result =
        Task.async(fn ->
          {MasterRule.for_date(~D[2013-07-01]), MasterRule.get(:mr4).emz}
        end)
        |> Task.await()

      assert result == {:mr1_2, true}
    end
  end

  describe "the cache" do
    setup do
      Application.put_env(:millennium_quiz, MasterRules, cache: true)
      MasterRules.clear_cache()

      on_exit(fn ->
        Application.put_env(:millennium_quiz, MasterRules, cache: false)
        MasterRules.clear_cache()
      end)
    end

    defp change_row_behind_the_cache do
      Repo.update_all(row("mr3"), set: [starts_on: ~D[2015-01-01]])
    end

    test "a read is kept until a save clears it" do
      assert MasterRules.dates().mr3 == ~D[2014-01-01]
      change_row_behind_the_cache()
      # still the cached value: the table was not read again
      assert MasterRules.dates().mr3 == ~D[2014-01-01]

      assert {:ok, _} = MasterRules.save(put(%{"mr3" => "2013-06-01"}))
      assert MasterRules.dates().mr3 == ~D[2013-06-01]
    end

    test "reset and import clear it too" do
      assert MasterRules.dates().mr3 == ~D[2014-01-01]
      change_row_behind_the_cache()
      assert MasterRules.dates().mr3 == ~D[2014-01-01]
      assert {:ok, _} = MasterRules.reset()
      assert MasterRules.dates().mr3 == ~D[2014-01-01]
      assert Repo.one!(row("mr3")).starts_on == ~D[2014-01-01]

      section = MasterRules.export()
      change_row_behind_the_cache()
      assert MasterRules.dates().mr3 == ~D[2014-01-01]
      assert {:ok, _} = MasterRules.import(section)
      assert Repo.one!(row("mr3")).starts_on == ~D[2014-01-01]
    end

    test "clear_cache/0 makes the next read go to the table" do
      assert MasterRules.dates().mr3 == ~D[2014-01-01]
      change_row_behind_the_cache()
      MasterRules.clear_cache()
      assert MasterRules.dates().mr3 == ~D[2015-01-01]
    end
  end

  describe "backup" do
    setup do
      CardSourcesStub.stub!()
      Repo.delete_all(Format)
      :ok
    end

    defp quiz_map do
      format_fixture(%{"name" => "Only", "date" => "2010-03-01"})
      map = Export.build()
      Repo.delete_all(Format)
      map
    end

    test "the export has a separate top-level master_rules section" do
      assert %{"master_rules" => %{"rules" => rules, "features" => features}} = Export.build()

      assert rules == [
               %{
                 "key" => "mr1_2",
                 "name" => "Master Rule 1/2",
                 "starts_on" => nil,
                 "emz" => false,
                 "pendulum_scales" => false
               },
               %{
                 "key" => "mr3",
                 "name" => "Master Rule 3",
                 "starts_on" => "2014-01-01",
                 "emz" => false,
                 "pendulum_scales" => true
               },
               %{
                 "key" => "mr4",
                 "name" => "Master Rule 4",
                 "starts_on" => "2017-04-01",
                 "emz" => true,
                 "pendulum_scales" => true
               }
             ]

      assert features == [%{"key" => "xyz", "starts_on" => "2011-06-01"}]
    end

    test "a round trip restores changed dates" do
      {:ok, _} = MasterRules.save(put(%{"mr3" => "2013-06-01", "xyz" => "2012-01-01"}))
      json = Export.to_json()
      {:ok, _} = MasterRules.reset()

      assert {:ok, summary} = Import.run(json)
      assert summary.master_rules == :applied
      assert summary.warnings == []

      assert MasterRules.dates() == %{
               mr3: ~D[2013-06-01],
               mr4: ~D[2017-04-01],
               xyz: ~D[2012-01-01]
             }

      assert "Master Rules: start dates restored" in MillenniumQuiz.Release.import_report(
               {:ok, summary}
             )
    end

    test "a file without the section leaves the settings alone" do
      {:ok, _} = MasterRules.save(put(%{"mr3" => "2013-06-01"}))
      json = quiz_map() |> Map.delete("master_rules") |> Jason.encode!()

      assert {:ok, summary} = Import.run(json)
      assert summary.formats_created == 1
      refute Map.has_key?(summary, :master_rules)
      assert MasterRules.dates().mr3 == ~D[2013-06-01]
    end

    test "an invalid section is reported and ignored, the import still works" do
      {:ok, _} = MasterRules.save(put(%{"mr3" => "2013-06-01"}))
      before = MasterRules.dates()
      good = quiz_map()

      for bad <- [
            "nonsense",
            %{},
            %{"rules" => [], "features" => []},
            %{
              "rules" => [
                %{"key" => "mr3", "starts_on" => "2018-01-01"},
                %{"key" => "mr4", "starts_on" => "2017-04-01"}
              ],
              "features" => [%{"key" => "xyz", "starts_on" => "2011-06-01"}]
            },
            %{
              "rules" => [
                %{"key" => "mr3", "starts_on" => "tomorrow"},
                %{"key" => "mr4", "starts_on" => 5}
              ],
              "features" => [%{"key" => "xyz", "starts_on" => "2011-06-01"}]
            }
          ] do
        Repo.delete_all(Format)
        json = good |> Map.put("master_rules", bad) |> Jason.encode!()

        assert {:ok, summary} = Import.run(json, pause_ms: 0)
        assert summary.formats_created == 1
        assert Enum.any?(summary.warnings, &(&1 =~ "Master Rules section ignored"))
        refute Map.has_key?(summary, :master_rules)
        assert MasterRules.dates() == before
      end
    end

    test "every committed backup file imports and leaves the settings alone" do
      {:ok, _} = MasterRules.save(put(%{"mr3" => "2013-06-01"}))

      files = Path.wildcard(Path.expand("../../../backups/*.json", __DIR__))
      assert files != []

      for file <- files do
        Repo.delete_all(Format)
        json = File.read!(file)
        refute json =~ "master_rules"
        assert {:ok, summary} = Import.run(json, pause_ms: 0)
        assert summary.formats_failed == []
        refute Map.has_key?(summary, :master_rules)
        assert MasterRules.dates().mr3 == ~D[2013-06-01], file
      end
    end
  end
end
