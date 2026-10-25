defmodule Mix.Tasks.Avatars.Fetch do
  @shortdoc "Downloads the player avatars (crops of the faces in card artwork)"
  @moduledoc """
  Downloads the artwork of every monster in `MillenniumQuiz.Avatars` from
  YGOPRODeck once, cuts out the face (the `face` square of the pool) and
  writes it as a small square JPEG to
  `priv/static/images/avatars/`. Commit the result; the app serves the files
  as they are.

      mix avatars.fetch
  """
  use Mix.Task

  alias MillenniumQuiz.Avatars
  alias Vix.Vips.Operation

  @size 128
  @dir "priv/static/images/avatars"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:req)
    File.mkdir_p!(@dir)

    for %{slug: slug, password: password, face: {x, y, size}} <- Avatars.all() do
      url = "https://images.ygoprodeck.com/images/cards_cropped/#{password}.jpg"
      %Req.Response{status: 200, body: body} = Req.get!(url, decode_body: false)

      {:ok, image} = Vix.Vips.Image.new_from_buffer(body)
      {:ok, face} = Operation.extract_area(image, x, y, size, size)
      {:ok, image} = Operation.thumbnail_image(face, @size, height: @size)

      {:ok, jpeg} = Vix.Vips.Image.write_to_buffer(image, ".jpg[Q=85,strip]")
      File.write!(Path.join(@dir, "#{slug}.jpg"), jpeg)
      Mix.shell().info("#{slug}: #{byte_size(jpeg)} bytes")
      Process.sleep(200)
    end
  end
end
