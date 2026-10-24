defmodule MillenniumQuiz.Games.Expiry do
  @moduledoc """
  Deletes stale games now and then (see `MillenniumQuiz.Games.delete_expired/1`).

  Started only where `:game_expiry_days` is configured. Runs once shortly after
  boot and then every six hours.
  """
  use GenServer

  require Logger

  @first_run :timer.minutes(1)
  @interval :timer.hours(6)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    state = %{interval: Keyword.get(opts, :interval, @interval)}
    Process.send_after(self(), :run, Keyword.get(opts, :first_run, @first_run))
    {:ok, state}
  end

  @impl true
  def handle_info(:run, state) do
    try do
      count = MillenniumQuiz.Games.delete_expired()
      Logger.info("Deleted #{count} expired games")
    rescue
      error -> Logger.error("Deleting expired games failed: #{Exception.message(error)}")
    end

    Process.send_after(self(), :run, state.interval)
    {:noreply, state}
  end
end
