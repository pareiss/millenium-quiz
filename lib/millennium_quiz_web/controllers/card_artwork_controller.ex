defmodule MillenniumQuizWeb.CardArtworkController do
  @moduledoc "Serves card artworks from the local card pool."
  use MillenniumQuizWeb, :controller

  alias MillenniumQuiz.Cards

  # Postgres bigint range; larger ids can't exist and would fail to encode.
  @max_id 9_223_372_036_854_775_807

  def show(conn, %{"id" => id}) do
    with {id, ""} when id in 1..@max_id <- Integer.parse(id),
         %{} = artwork <- Cards.artwork_info(id) do
      etag = ~s("#{artwork.artwork_id}-#{DateTime.to_unix(artwork.fetched_at)}")

      # The image comes from a remote source: never let a browser treat it as
      # anything but an image.
      conn =
        conn
        |> put_resp_header("etag", etag)
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")

      if etag in get_req_header(conn, "if-none-match") do
        send_resp(conn, 304, "")
      else
        conn
        |> put_resp_content_type(artwork.content_type, nil)
        |> send_resp(200, Cards.artwork_data(id))
      end
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end
end
