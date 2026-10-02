defmodule MillenniumQuizWeb.CardArtworkControllerTest do
  use MillenniumQuizWeb.ConnCase, async: true

  alias MillenniumQuiz.{Cards, CardSourcesStub}

  test "serves artworks from the card pool, with caching", %{conn: conn} do
    CardSourcesStub.stub!()
    {:ok, reborn} = Cards.import(83_764_719)

    conn = get(conn, ~p"/cards/#{reborn.id}/artwork")
    assert response(conn, 200) == CardSourcesStub.artwork()
    assert response_content_type(conn, :jpeg) =~ "image/jpeg"
    [etag] = get_resp_header(conn, "etag")

    cached =
      build_conn()
      |> put_req_header("if-none-match", etag)
      |> get(~p"/cards/#{reborn.id}/artwork")

    assert response(cached, 304)
  end

  test "unknown cards and cards without artwork are 404", %{conn: conn} do
    assert conn |> get(~p"/cards/0/artwork") |> response(404)
    assert build_conn() |> get("/cards/abc/artwork") |> response(404)
  end
end
