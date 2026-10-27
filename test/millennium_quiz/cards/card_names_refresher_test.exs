defmodule MillenniumQuiz.Cards.CardNames.RefresherTest do
  use MillenniumQuiz.DataCase, async: false

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

  test "a refresh that failed leaves the list due, so the next check tries again" do
    test = self()

    start_refresher(
      interval_ms: 50,
      refresh: fn ->
        send(test, :tried)
        {:error, {:http, 500}, 1}
      end
    )

    assert_receive :tried, 1_000
    assert_receive :tried, 1_000
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
