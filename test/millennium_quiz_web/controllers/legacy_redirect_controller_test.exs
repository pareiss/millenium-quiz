defmodule MillenniumQuizWeb.LegacyRedirectControllerTest do
  use MillenniumQuizWeb.ConnCase, async: true

  defp redirect_of(path), do: build_conn() |> get(path) |> redirected_to(301)

  test "player links keep their path and query string" do
    assert redirect_of("/categories/5/play?players[]=Ann&mode=free") ==
             "/formats/5/play?players[]=Ann&mode=free"
  end

  test "admin links, from the index to nested pages" do
    assert redirect_of("/admin/categories") == "/admin/formats"
    assert redirect_of("/admin/categories/new") == "/admin/formats/new"
    assert redirect_of("/admin/categories/5") == "/admin/formats/5"
    assert redirect_of("/admin/categories/5/edit") == "/admin/formats/5/edit"
  end

  test "encoded characters stay encoded" do
    assert redirect_of("/categories/a%2Fb%3Fc/play") == "/formats/a%2Fb%3Fc/play"
    assert redirect_of("/admin/categories/x%23y") == "/admin/formats/x%23y"
  end
end
