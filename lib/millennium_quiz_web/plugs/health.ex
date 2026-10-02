defmodule MillenniumQuizWeb.Plugs.Health do
  @moduledoc """
  Kubernetes probes, answered before the router (no session, no logging):

    * `GET /healthz/live`  - the BEAM is up (liveness, no DB check so a DB
      outage does not restart the app)
    * `GET /healthz/ready` - the database answers (readiness)
  """
  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "GET", path_info: ["healthz", "live"]} = conn, _opts) do
    conn |> send_resp(200, "ok") |> halt()
  end

  def call(%Plug.Conn{method: "GET", path_info: ["healthz", "ready"]} = conn, _opts) do
    case Ecto.Adapters.SQL.query(MillenniumQuiz.Repo, "SELECT 1", []) do
      {:ok, _} -> conn |> send_resp(200, "ok") |> halt()
      {:error, _} -> conn |> send_resp(503, "database unavailable") |> halt()
    end
  end

  def call(conn, _opts), do: conn
end
