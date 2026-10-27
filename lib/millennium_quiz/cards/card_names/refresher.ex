defmodule MillenniumQuiz.Cards.CardNames.Refresher do
  @moduledoc """
  Keeps the list of card names (`MillenniumQuiz.Cards.CardNames`) fresh from
  inside the running application, so it uses the node's own YGOPRODeck gate
  (one budget for everything) and nobody has to run a command after a deploy.

  A minute after start, and then every `interval_ms`, it checks the list and
  refreshes it when it is empty or older than `max_age_days`. The refresh runs
  in a task under `MillenniumQuiz.TaskSupervisor` and never crashes this
  process: a failure (YGOPRODeck down, the table not migrated yet) is logged
  and tried again at the next check: a failed refresh writes nothing
  (`CardNames.refresh/1`), so the list is still due.

      config :millennium_quiz, MillenniumQuiz.Cards.CardNames.Refresher,
        enabled: false  # the test suite does this

  See `defaults/0` for the other options.
  """
  use GenServer

  require Logger

  alias MillenniumQuiz.Cards.CardNames

  @defaults [
    enabled: true,
    initial_delay_ms: :timer.seconds(60),
    interval_ms: :timer.hours(6),
    max_age_days: 7,
    refresh: &CardNames.refresh/0,
    supervisor: MillenniumQuiz.TaskSupervisor
  ]

  def defaults, do: @defaults

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)

  @impl true
  def init(opts) do
    opts =
      @defaults
      |> Keyword.merge(Application.get_env(:millennium_quiz, __MODULE__, []))
      |> Keyword.merge(opts)

    if opts[:enabled], do: Process.send_after(self(), :check, opts[:initial_delay_ms])
    {:ok, %{opts: opts, task: nil}}
  end

  @impl true
  def handle_info(:check, %{opts: opts, task: task} = state) do
    Process.send_after(self(), :check, opts[:interval_ms])

    if is_nil(task) and stale?(opts[:max_age_days]) do
      task = Task.Supervisor.async_nolink(opts[:supervisor], fn -> run(opts[:refresh]) end)
      {:noreply, %{state | task: task}}
    else
      {:noreply, state}
    end
  end

  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, count} -> Logger.info("Card names refreshed: #{count} written")
      other -> Logger.warning("Card names refresh did not finish: #{inspect(other)}")
    end

    {:noreply, %{state | task: nil}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: %Task{ref: ref}} = state) do
    Logger.warning("Card names refresh crashed: #{inspect(reason)}")
    {:noreply, %{state | task: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # a database that is not migrated yet must not take anything down
  defp stale?(max_age_days) do
    CardNames.stale?(max_age_days)
  rescue
    error ->
      Logger.warning("Card names: could not read the list: #{Exception.message(error)}")
      false
  end

  defp run(refresh) do
    refresh.()
  rescue
    error -> {:error, Exception.message(error)}
  end
end
