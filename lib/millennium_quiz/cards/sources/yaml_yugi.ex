defmodule MillenniumQuiz.Cards.Sources.YamlYugi do
  @moduledoc """
  Current names and texts in every language from YAML Yugi
  (https://github.com/DawnbrandBots/yaml-yugi), served by the jsDelivr CDN.
  """
  alias MillenniumQuiz.Cards.Sources.HTTP

  @base_url "https://cdn.jsdelivr.net/gh/DawnbrandBots/yaml-yugi/data/cards"

  @doc """
  Returns `%{password, konami_id, yugipedia_page_id, names, texts}` for the
  first of `passwords` YAML Yugi knows (alternate artworks have their own ids).
  """
  def fetch(passwords) when is_list(passwords) do
    Enum.reduce_while(passwords, {:error, :not_found}, fn password, not_found ->
      case fetch(password) do
        {:error, :not_found} -> {:cont, not_found}
        result -> {:halt, result}
      end
    end)
  end

  def fetch(password) when is_integer(password) do
    path = "/#{String.pad_leading(Integer.to_string(password), 8, "0")}.json"

    case Req.get(HTTP.new(@base_url), url: path) do
      {:ok, %{status: 200, body: body}} ->
        body = if is_binary(body), do: Jason.decode!(body), else: body

        {:ok,
         %{
           password: body["password"] || password,
           konami_id: body["konami_id"],
           yugipedia_page_id: body["yugipedia_page_id"],
           names: plain(body["name"]),
           texts: plain(body["text"])
         }}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Japanese names come with <ruby> readings; keep the base text only.
  defp plain(nil), do: %{}

  defp plain(map) do
    map
    |> Enum.reject(fn {_, value} -> is_nil(value) end)
    |> Map.new(fn {lang, value} ->
      {lang, value |> String.replace(~r/<rt>.*?<\/rt>/, "") |> String.replace(~r/<[^>]+>/, "")}
    end)
  end
end
