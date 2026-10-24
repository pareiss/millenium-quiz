defmodule MillenniumQuizWeb.CardArtworkController do
  @moduledoc "Serves card artworks from the local card pool."
  use MillenniumQuizWeb, :controller

  alias MillenniumQuiz.{Cards, RateLimit}
  alias MillenniumQuizWeb.ClientIP

  # Postgres bigint range; larger ids can't exist and would fail to encode.
  @max_id 9_223_372_036_854_775_807

  def show(conn, %{"id" => id} = params) do
    with {id, ""} when id in 1..@max_id <- Integer.parse(id),
         %{} = artwork <- Cards.artwork_info(id) do
      base_etag = "#{artwork.artwork_id}-#{DateTime.to_unix(artwork.fetched_at)}"
      width = width(params)
      etag = if width, do: ~s("#{base_etag}-#{width}"), else: ~s("#{base_etag}")

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
        send_image(conn, id, artwork, width, base_etag)
      end
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp send_image(conn, id, artwork, width, base_etag) do
    case width && resize(conn, id, artwork, width) do
      {:ok, jpeg} ->
        conn
        |> put_resp_content_type("image/jpeg", nil)
        |> send_resp(200, jpeg)

      result ->
        # no (valid) width, resizing failed or the client is over its limit: the
        # original, under its own ETag. Over the limit it is only kept briefly
        # under the resized URL, so the real rendition is fetched later.
        conn =
          if result == :limited,
            do: put_resp_header(conn, "cache-control", "private, max-age=60"),
            else: conn

        conn
        |> put_resp_header("etag", ~s("#{base_etag}"))
        |> put_resp_content_type(artwork.content_type, nil)
        |> send_resp(200, Cards.artwork_data(id))
    end
  end

  # Only a cache miss is expensive. Over the per-client limit the original is
  # served instead (never a 429 for an image).
  defp resize(conn, id, artwork, width) do
    if Cards.resized_artwork_cached?(id, artwork, width) or resize_allowed?(conn),
      do: Cards.resized_artwork(id, artwork, width),
      else: :limited
  end

  defp resize_allowed?(conn) do
    RateLimit.check_rule(:artwork_resize_ip, ClientIP.from_conn(conn)) == :ok
  end

  # `?w=` is one of the offered widths; anything else means the original, so
  # URLs never break.
  defp width(%{"w" => w}) when is_binary(w) do
    case Integer.parse(w) do
      {width, ""} -> if width in Cards.artwork_widths(), do: width
      _ -> nil
    end
  end

  defp width(_), do: nil
end
