defmodule MillenniumQuiz.ArtworkFixtures do
  @moduledoc "Real (generated) card artworks for the resizing tests."

  alias MillenniumQuiz.Cards.{Card, CardArtwork}
  alias MillenniumQuiz.Repo

  @doc "A noisy JPEG of `size` x `size` pixels."
  def jpeg(size \\ 624) do
    image = Vix.Vips.Operation.gaussnoise!(size, size, mean: 128.0, sigma: 40.0)
    {:ok, data} = Vix.Vips.Image.write_to_buffer(image, ".jpg[Q=95]")
    data
  end

  @doc "Width and height of an image given as binary."
  def dimensions(data) do
    {:ok, image} = Vix.Vips.Image.new_from_buffer(data)
    {Vix.Vips.Image.width(image), Vix.Vips.Image.height(image)}
  end

  @doc "A card with a stored artwork; returns the card."
  def card_with_artwork(data \\ jpeg(), content_type \\ "image/jpeg") do
    card =
      Repo.insert!(%Card{
        name: "Art Card #{System.unique_integer([:positive])}",
        password: System.unique_integer([:positive]),
        fetched_at: DateTime.utc_now(:second)
      })

    Repo.insert!(%CardArtwork{
      card_id: card.id,
      artwork_id: card.password,
      content_type: content_type,
      data: data,
      source_url: "https://example.test/art.jpg",
      fetched_at: DateTime.utc_now(:second)
    })

    card
  end
end
