defmodule MillenniumQuizWeb.LegacyRedirectController do
  @moduledoc "Keeps links from before categories were renamed to formats working."
  use MillenniumQuizWeb, :controller

  # The rest of the path is taken from the raw request path, so encoded
  # characters (e.g. %2F, %3F) stay encoded in the redirect target.
  def formats(conn, _params) do
    {old, new} =
      if hd(conn.path_info) == "admin",
        do: {"/admin/categories", "/admin/formats"},
        else: {"/categories", "/formats"}

    rest = String.replace_prefix(conn.request_path, old, "")
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: new <> rest <> query)
  end
end
