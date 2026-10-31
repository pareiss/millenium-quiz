defmodule Mix.Tasks.Avatars.FetchTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Avatars.Fetch

  @entries [%{slug: "have"}, %{slug: "missing"}]
  defp exists?(path), do: String.ends_with?(path, "/have.jpg")

  test "only the images that are missing are fetched" do
    assert Fetch.to_fetch(@entries, false, &exists?/1) == [%{slug: "missing"}]
  end

  test "--force fetches all of them again" do
    assert Fetch.to_fetch(@entries, true, &exists?/1) == @entries
  end
end
