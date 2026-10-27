defmodule MillenniumQuiz.Cards.CardNamesTest do
  use MillenniumQuiz.DataCase, async: true

  alias MillenniumQuiz.CardSourcesStub
  alias MillenniumQuiz.Cards.{CardName, CardNames}

  @today ~D[2026-10-27]

  setup do
    CardSourcesStub.stub!()
    :ok
  end

  defp add(name, password, date, attrs \\ %{}) do
    Repo.insert!(
      struct!(
        CardName,
        Map.merge(
          %{name: name, password: password, passwords: [password], tcg_release_date: date},
          attrs
        )
      )
    )
  end

  defp names(results), do: Enum.map(results, & &1.name)

  describe "windows/1" do
    test "up to 2002, one per year, then everything later" do
      windows = CardNames.windows(@today)

      assert hd(windows) == {~D[1990-01-01], ~D[2002-12-31]}
      assert {~D[2003-01-01], ~D[2003-12-31]} in windows
      assert {~D[2026-01-01], ~D[2026-12-31]} in windows
      assert List.last(windows) == {~D[2027-01-01], ~D[2099-12-31]}
      assert length(windows) == 1 + (2026 - 2003 + 1) + 1
    end
  end

  describe "refresh/1" do
    test "stores the cards of every window, and again without doubling them" do
      assert {:ok, 2} = CardNames.refresh(today: @today)
      assert CardNames.count() == 2
      assert CardNames.refreshed_at()

      reborn = Repo.get_by!(CardName, name: "Monster Reborn")
      assert reborn.konami_id == 4842
      assert reborn.tcg_release_date == ~D[2002-03-08]
      assert reborn.password == 83_764_719
      assert reborn.password in reborn.passwords
      assert length(reborn.passwords) == 2

      assert {:ok, 2} = CardNames.refresh(today: @today)
      assert CardNames.count() == 2
    end

    test "updates what changed" do
      add("Monster Reborn (old)", 83_764_719, ~D[2002-03-08])

      assert {:ok, 2} = CardNames.refresh(today: @today)

      assert CardNames.count() == 2
      assert Repo.get_by!(CardName, password: 83_764_719).name == "Monster Reborn"
    end

    test "keeps what it has and says so when a request fails" do
      Req.Test.stub(MillenniumQuiz.Cards, fn conn ->
        if conn.query_string =~ "startdate=2003",
          do: Plug.Conn.send_resp(conn, 500, "no"),
          else: CardSourcesStub.handle(conn)
      end)

      assert {:error, {:http, 500}, 1} = CardNames.refresh(today: @today)
      assert CardNames.count() == 1
    end
  end

  describe "stale?/2" do
    test "is true for an empty list and for one older than the limit" do
      assert CardNames.stale?(7)

      add("Some Card", 1, ~D[2010-01-01])
      refute CardNames.stale?(7)
      assert CardNames.stale?(7, DateTime.add(DateTime.utc_now(), 8, :day))
      refute CardNames.stale?(7, DateTime.add(DateTime.utc_now(), 6, :day))
    end
  end

  describe "refresh/1 pruning" do
    test "deletes rows the refresh did not see (a card listed under another id now)" do
      long_ago = DateTime.add(DateTime.utc_now(:second), -8, :day)

      add("Monster Reborn", 99, ~D[2002-03-08], %{
        konami_id: 4842,
        inserted_at: long_ago,
        updated_at: long_ago
      })

      add("Plain Card", 11_111_111, ~D[2015-05-05], %{inserted_at: long_ago, updated_at: long_ago})

      assert {:ok, 2} = CardNames.refresh(today: @today)

      assert Enum.sort(Enum.map(Repo.all(CardName), & &1.password)) ==
               [11_111_111, 83_764_719]
    end

    test "keeps everything when the refresh wrote far fewer names than the list held" do
      for n <- 1..10, do: add("Old Card #{n}", 500 + n, ~D[2010-01-01])

      assert {:ok, 2} = CardNames.refresh(today: @today)

      assert CardNames.count() == 12
    end

    test "keeps everything when a request failed" do
      add("Old Card", 500, ~D[2010-01-01])

      Req.Test.stub(MillenniumQuiz.Cards, fn conn ->
        if conn.query_string =~ "startdate=2003",
          do: Plug.Conn.send_resp(conn, 500, "no"),
          else: CardSourcesStub.handle(conn)
      end)

      assert {:error, {:http, 500}, 1} = CardNames.refresh(today: @today)
      assert Repo.get_by(CardName, password: 500)
    end
  end

  describe "search/2" do
    test "ranks like the pool's suggestions" do
      add("Dark Hole Dragon", 1, ~D[2010-01-01])
      add("Red Dark", 2, ~D[2010-01-01])
      add("Darkness", 3, ~D[2010-01-01])
      add("Dark", 4, ~D[2010-01-01])

      assert ["Dark", "Dark Hole Dragon", "Darkness", "Red Dark"] =
               names(CardNames.search("dark", @today))
    end

    test "lists only cards released by the date" do
      add("Old Dragon", 1, ~D[2004-01-01])
      add("New Dragon", 2, ~D[2020-01-01])
      add("Undated Dragon", 3, nil)

      assert ["Old Dragon"] = names(CardNames.search("dragon", ~D[2010-01-01]))
      assert ["New Dragon", "Old Dragon"] = names(CardNames.search("dragon", ~D[2021-01-01]))
    end

    test "takes % and _ literally and stops at 20" do
      add("100% Dragon", 1, ~D[2010-01-01])
      add("Plain Dragon", 2, ~D[2010-01-01])
      assert ["100% Dragon"] = names(CardNames.search("0% d", @today))

      for n <- 1..25, do: add("Many Dragon #{n}", 100 + n, ~D[2010-01-01])
      assert length(CardNames.search("many", @today)) == 20
    end

    test "answers like the remote search" do
      add("Monster Reborn", 83_764_718, ~D[2002-03-08], %{
        passwords: [83_764_719, 83_764_718],
        konami_id: 4842,
        card_type: "Normal Spell",
        frame_type: "spell"
      })

      assert [
               %{
                 password: 83_764_718,
                 passwords: [83_764_719, 83_764_718],
                 konami_id: 4842,
                 name: "Monster Reborn",
                 card_type: "Normal Spell",
                 frame_type: "spell",
                 tcg_release_date: ~D[2002-03-08]
               }
             ] = CardNames.search("reborn", @today)
    end
  end
end
