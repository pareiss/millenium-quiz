defmodule MillenniumQuiz.Avatars do
  @moduledoc """
  The monsters whose faces are the players' pictures. Each player of a game
  gets a different one (see `assign/2`); the images are square crops of the
  faces in the cards' artwork in `priv/static/images/avatars/<slug>.jpg`, written once by
  `mix avatars.fetch` and committed, so a running app needs neither the card
  pool nor the network for them.
  """

  # `password` is the id of the card on YGOPRODeck; `face` is the square
  # `{x, y, size}` around the face in its 624x624 artwork.
  @pool [
    %{
      slug: "elemental-hero-stratos",
      name: "Elemental HERO Stratos",
      password: 40_044_918,
      face: {135, 45, 190}
    },
    %{
      slug: "blackwing-vayu-the-emblem-of-honor",
      name: "Blackwing - Vayu the Emblem of Honor",
      password: 72_714_392,
      face: {190, 85, 230}
    },
    %{slug: "dark-grepher", name: "Dark Grepher", password: 14_536_035, face: {250, 0, 190}},
    %{slug: "jinzo", name: "Jinzo", password: 77_585_513, face: {180, 5, 230}},
    %{
      slug: "gladiator-beast-bestiari",
      name: "Gladiator Beast Bestiari",
      password: 41_470_137,
      face: {240, 30, 180}
    },
    %{slug: "treeborn-frog", name: "Treeborn Frog", password: 12_538_374, face: {175, 20, 190}},
    %{
      slug: "caius-the-shadow-monarch",
      name: "Caius the Shadow Monarch",
      password: 9_748_752,
      face: {205, 10, 200}
    },
    %{
      slug: "blackwing-shura-the-blue-flame",
      name: "Blackwing - Shura the Blue Flame",
      password: 58_820_853,
      face: {180, 45, 190}
    }
  ]

  @slugs Enum.map(@pool, & &1.slug)

  @doc "Every monster of the pool: `%{slug, name, password, face}`."
  def all, do: @pool

  @doc """
  `count` different slugs from the pool, chosen with `shuffle` (as in
  `Game.new/4`). With more players than monsters they repeat.
  """
  def assign(count, shuffle \\ &Enum.shuffle/1) when is_integer(count) and count >= 0 do
    @slugs |> shuffle.() |> Stream.cycle() |> Enum.take(count)
  end

  @doc "The image path of `slug`, or nil for nil or a slug that isn't in the pool."
  def path(slug) when slug in @slugs, do: "/images/avatars/#{slug}.jpg"
  def path(_), do: nil

  @doc "The monster's name, or nil for an unknown slug."
  def name(slug), do: Enum.find_value(@pool, &(&1.slug == slug && &1.name))
end
