defmodule MillenniumQuizWeb.LegacyRedirectController do
  @moduledoc "Keeps links from before categories were renamed to formats working."
  use MillenniumQuizWeb, :controller

  def formats(conn, %{"path" => path}) do
    prefix = if hd(conn.path_info) == "admin", do: "/admin/formats", else: "/formats"
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: Enum.join([prefix | path], "/") <> query)
  end
end
