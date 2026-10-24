defmodule MillenniumQuizWeb.EventLimit do
  @moduledoc """
  `on_mount` hook that rate-limits the events of one LiveView socket (rule
  `:socket_events`, keyed on the socket process), so a client can't flood a
  game or form with events. Events over the limit are dropped silently.
  """
  import Phoenix.LiveView

  alias MillenniumQuiz.RateLimit

  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :event_limit, :handle_event, &limit/3)}
  end

  defp limit(_event, _params, socket) do
    case RateLimit.check_rule(:socket_events, {:sock, inspect(self())}) do
      :ok -> {:cont, socket}
      {:error, _} -> {:halt, socket}
    end
  end
end
