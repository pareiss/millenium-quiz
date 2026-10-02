defmodule MillenniumQuizWeb.CardArtworkController do
  @moduledoc "Serves card artworks from the local card pool."
  use MillenniumQuizWeb, :controller

  alias MillenniumQuiz.Cards

  def show(conn, %{"id" => id}) do
    with {id, ""} <- Integer.parse(id),
         %{} = artwork <- Cards.get_artwork(id) do
      etag = ~s("#{artwork.artwork_id}-#{DateTime.to_unix(artwork.fetched_at)}")

      conn = put_resp_header(conn, "etag", etag)

      if etag in get_req_header(conn, "if-none-match") do
        send_resp(conn, 304, "")
      else
        conn
        |> put_resp_content_type(artwork.content_type, nil)
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> send_resp(200, artwork.data)
      end
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end
end
