defmodule Mix.Tasks.Avatars.Fetch do
  @shortdoc "Downloads the player avatars (crops of the faces in card artwork)"
  @moduledoc """
  Downloads the artwork of every monster in `MillenniumQuiz.Avatars` (the
  default pool and the sets of the formats) from YGOPRODeck once, cuts out the
  face (the `face` square of the entry) and writes it as a small square JPEG to
  `priv/static/images/avatars/`. Commit the result; the app serves the files
  as they are.

      mix avatars.fetch           # only the images that are missing
      mix avatars.fetch --force   # all of them again (after changing a `face`)
  """
  use Mix.Task

  alias MillenniumQuiz.Avatars
  alias Vix.Vips.Operation

  @size 128
  @dir "priv/static/images/avatars"

  @doc """
  The entries whose image has to be downloaded: all of them with `force?`,
  else those whose file (`exists?` is asked for its path) is missing.
  """
  def to_fetch(entries, force?, exists?) do
    Enum.filter(entries, &(force? or not exists?.(image_path(&1.slug))))
  end

  defp image_path(slug), do: Path.join(@dir, "#{slug}.jpg")

  @impl Mix.Task
  def run(args) do
    force? = "--force" in args
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:req)
    File.mkdir_p!(@dir)

    for %{slug: slug, password: password, face: {x, y, size}} <-
          to_fetch(Avatars.all(), force?, &File.exists?/1) do
      url = "https://images.ygoprodeck.com/images/cards_cropped/#{password}.jpg"
      %Req.Response{status: 200, body: body} = Req.get!(url, decode_body: false)

      {:ok, image} = Vix.Vips.Image.new_from_buffer(body)
      {:ok, face} = Operation.extract_area(image, x, y, size, size)
      {:ok, image} = Operation.thumbnail_image(face, @size, height: @size)

      {:ok, jpeg} = Vix.Vips.Image.write_to_buffer(image, ".jpg[Q=85,strip]")
      File.write!(image_path(slug), jpeg)
      Mix.shell().info("#{slug}: #{byte_size(jpeg)} bytes")
      Process.sleep(200)
    end
  end
end
