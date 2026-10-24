defmodule MillenniumQuizWeb.CardArtworkControllerTest do
  use MillenniumQuizWeb.ConnCase, async: true

  alias MillenniumQuiz.{Cards, CardSourcesStub}
  import MillenniumQuiz.ArtworkFixtures

  test "serves artworks from the card pool, with caching", %{conn: conn} do
    CardSourcesStub.stub!()
    {:ok, reborn} = Cards.import(83_764_719)

    conn = get(conn, ~p"/cards/#{reborn.id}/artwork")
    assert response(conn, 200) == CardSourcesStub.artwork()
    assert response_content_type(conn, :jpeg) =~ "image/jpeg"
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "default-src 'none'"
    [etag] = get_resp_header(conn, "etag")

    cached =
      build_conn()
      |> put_req_header("if-none-match", etag)
      |> get(~p"/cards/#{reborn.id}/artwork")

    assert response(cached, 304)
    assert get_resp_header(cached, "cache-control") == ["public, max-age=86400"]
  end

  test "unknown cards and cards without artwork are 404", %{conn: conn} do
    assert conn |> get(~p"/cards/0/artwork") |> response(404)
    assert build_conn() |> get("/cards/abc/artwork") |> response(404)
    # beyond the database's integer range
    assert build_conn() |> get("/cards/99999999999999999999/artwork") |> response(404)
  end

  describe "resized renditions" do
    setup do
      data = jpeg()
      %{card: card_with_artwork(data), data: data}
    end

    test "?w=200 and ?w=400 are smaller JPEGs under their own ETags", %{
      conn: conn,
      card: card,
      data: data
    } do
      original = get(conn, ~p"/cards/#{card.id}/artwork")
      assert response(original, 200) == data
      [original_etag] = get_resp_header(original, "etag")

      for width <- [200, 400] do
        conn = get(build_conn(), ~p"/cards/#{card.id}/artwork?w=#{width}")
        body = response(conn, 200)

        assert response_content_type(conn, :jpeg) =~ "image/jpeg"
        assert dimensions(body) == {width, width}
        assert byte_size(body) < byte_size(data)
        assert get_resp_header(conn, "cache-control") == ["public, max-age=86400"]
        assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
        assert [csp] = get_resp_header(conn, "content-security-policy")
        assert csp =~ "sandbox"

        [etag] = get_resp_header(conn, "etag")
        assert etag != original_etag
        assert etag == String.replace_suffix(original_etag, ~s("), ~s(-#{width}"))

        cached =
          build_conn()
          |> put_req_header("if-none-match", etag)
          |> get(~p"/cards/#{card.id}/artwork?w=#{width}")

        assert response(cached, 304)
      end
    end

    test "an artwork is not enlarged" do
      card = card_with_artwork(jpeg(150))
      conn = get(build_conn(), ~p"/cards/#{card.id}/artwork?w=400")
      assert dimensions(response(conn, 200)) == {150, 150}
    end

    test "an invalid or unoffered width serves the original", %{
      conn: conn,
      card: card,
      data: data
    } do
      [etag] = conn |> get(~p"/cards/#{card.id}/artwork") |> get_resp_header("etag")

      for w <- ["300", "0", "-200", "abc", "200px", "", "9999999999999999999999"] do
        conn = get(build_conn(), "/cards/#{card.id}/artwork", %{"w" => w})
        assert response(conn, 200) == data
        assert get_resp_header(conn, "etag") == [etag]
      end

      conn = get(build_conn(), "/cards/#{card.id}/artwork?w[]=200")
      assert response(conn, 200) == data
    end

    test "an artwork that can't be resized falls back to the original" do
      garbage = <<0xFF, 0xD8, 0xFF, 0xE0, "not really an image", 0xFF, 0xD9>>
      card = card_with_artwork(garbage)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          conn = get(build_conn(), ~p"/cards/#{card.id}/artwork?w=200")
          assert response(conn, 200) == garbage
          [etag] = get_resp_header(conn, "etag")
          refute etag =~ "-200"
        end)

      assert log =~ "Resizing artwork of card #{card.id} failed"
    end

    test "a failed resize is remembered: no new decoding or warning on the next request" do
      garbage = <<0xFF, 0xD8, 0xFF, 0xE0, "still not an image", 0xFF, 0xD9>>
      card = card_with_artwork(garbage)

      ExUnit.CaptureLog.capture_log(fn ->
        assert build_conn() |> get(~p"/cards/#{card.id}/artwork?w=400") |> response(200)
      end)

      # the cache takes inserts asynchronously
      MillenniumQuiz.Cards.ArtworkCache.stats()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          conn = get(build_conn(), ~p"/cards/#{card.id}/artwork?w=400")
          assert response(conn, 200) == garbage
        end)

      refute log =~ "Resizing artwork"
    end

    test "unknown cards are 404 with a width too" do
      assert build_conn() |> get("/cards/0/artwork?w=200") |> response(404)
      assert build_conn() |> get("/cards/987654321/artwork?w=200") |> response(404)
    end
  end
end
