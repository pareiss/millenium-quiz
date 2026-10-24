defmodule MillenniumQuiz.Cards.ArtworkImage do
  @moduledoc "Resizes card artworks (libvips, through the `image` library)."

  alias Vix.Vips.Operation

  @quality 80

  @doc """
  The artwork as a JPEG (quality #{@quality}, metadata stripped) that is
  `width` pixels wide, keeping the aspect ratio. Never enlarges: an artwork
  narrower than `width` keeps its size.
  """
  @spec resize(binary(), pos_integer()) :: {:ok, binary()} | {:error, term()}
  def resize(data, width) when is_binary(data) and width > 0 do
    # `height` is far above any artwork, so that only the width limits the size
    with {:ok, image} <-
           Operation.thumbnail_buffer(data, width, height: 100_000, size: :VIPS_SIZE_DOWN) do
      Vix.Vips.Image.write_to_buffer(image, ".jpg[Q=#{@quality},strip]")
    end
  rescue
    error -> {:error, error}
  end
end
