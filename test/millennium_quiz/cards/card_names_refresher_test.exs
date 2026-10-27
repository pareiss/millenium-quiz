defmodule MillenniumQuiz.Cards.CardNames.RefresherTest do
  use MillenniumQuiz.DataCase, async: false

  import Req.Test, only: [set_req_test_to_shared: 0]

  @moduletag :capture_log

  alias MillenniumQuiz.Cards.CardName
  alias MillenniumQuiz.Cards.CardNames.Refresher

  setup do
    start_supervised!({Task.Supervisor, name: :refresher_tasks})
    :ok
  end

  defp start_refresher(opts) do
    test = self()

    opts =
      Keyword.merge(
        [
          name: :"refresher_#{System.unique_integer([:positive])}",
          enabled: true,
          initial_delay_ms: 10,
          interval_ms: 60_000,
          supervisor: :refresher_tasks,
          refresh: fn ->
            send(test, :refreshed)
            {:ok, 0}
          end
        ],
        opts
      )

    pid = start_supervised!({Refresher, opts})
    Ecto.Adapters.SQL.Sandbox.allow(MillenniumQuiz.Repo, self(), pid)
    pid
  end

  defp add_name(updated_at) do
    Repo.insert!(%CardName{
      name: "Some Card",
      password: 1,
      passwords: [1],
      tcg_release_date: ~D[2010-01-01],
      inserted_at: updated_at,
      updated_at: updated_at
    })
  end

  test "refreshes an empty list" do
    start_refresher([])
    assert_receive :refreshed, 1_000
  end

  test "refreshes a list older than max_age_days" do
    add_name(DateTime.add(DateTime.utc_now(:second), -8, :day))
    start_refresher([])
    assert_receive :refreshed, 1_000
  end

  test "leaves a fresh list alone" do
    add_name(DateTime.utc_now(:second))
    start_refresher([])
    refute_receive :refreshed, 300
  end

  test "does nothing when disabled" do
    start_refresher(enabled: false)
    refute_receive :refreshed, 300
  end

  test "after a refresh that failed halfway the old list is still due: the next check tries again" do
    set_req_test_to_shared()
    long_ago = DateTime.add(DateTime.utc_now(:second), -8, :day)
    add_name(long_ago)

    # the real refresh, with a YGOPRODeck that fails from the 2003 window on
    Req.Test.stub(MillenniumQuiz.Cards, fn conn ->
      if conn.query_string =~ "startdate=2003",
        do: Plug.Conn.send_resp(conn, 500, "no"),
        else: MillenniumQuiz.CardSourcesStub.handle(conn)
    end)

    test = self()

    start_refresher(
      interval_ms: 100,
      refresh: fn ->
        send(test, :tried)
        MillenniumQuiz.Cards.CardNames.refresh()
      end
    )

    # a refresh that wrote its first window would leave a fresh timestamp behind,
    # and the second check would find the list fresh
    assert_receive :tried, 2_000
    assert_receive :tried, 2_000
    assert MillenniumQuiz.Cards.CardNames.stale?(7)
  end

  test "survives a refresh that raises and tries again at the next check" do
    test = self()

    start_refresher(
      interval_ms: 50,
      refresh: fn ->
        send(test, :tried)
        raise "YGOPRODeck is down"
      end
    )

    assert_receive :tried, 1_000
    assert_receive :tried, 1_000
  end
end
