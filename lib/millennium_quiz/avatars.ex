defmodule MillenniumQuiz.Avatars do
  @moduledoc """
  The monsters whose faces are the players' pictures. Each player of a game
  gets a different one (see `assign/3`); the images are square crops of the
  faces in the cards' artwork in `priv/static/images/avatars/<slug>.jpg`, written once by
  `mix avatars.fetch` and committed, so a running app needs neither the card
  pool nor the network for them.

  A format can have its own set of monsters (`for_format/1`, by the format's
  date, the one field of a format that never changes): the monsters of its popular deck types, so a game of Edison shows
  Blackwings and Lightsworn, a game of Goat shows Chaos Sorcerer and Don
  Zaloog. Every other format uses the default pool. The sets were made on
  2026-10-28 from the three cards each popular deck type shows on
  [Format Library](https://formatlibrary.com) (`/api/decks/popular/<format>`,
  whose card ids are the YGOPRODeck ids): monsters only, released by the
  format's date. They are written down here, nothing is asked of that site
  while the app runs. A game saves the slug of each player's picture, so games
  saved before a set existed keep theirs.

  An admin can instead choose cards from the card pool as the pictures of a
  format (`Quiz.add_avatar_card/2`); when a format has any, those are its set
  and the hardcoded ones are not used (`pool/1`). Such a picture has the slug
  `"card-<id>"` (`card_slug/1`, `card_id/1`) and is the card's artwork,
  served at `path/2`. The pure functions here never ask the database: the
  name of a card picture is `Quiz.avatar_cards/1`'s business, `name/1` is nil
  for it. If a card leaves the pool, games that saved its slug show no
  picture.
  """

  @max_card_id 9_223_372_036_854_775_807

  # `password` is the id of the card on YGOPRODeck; `face` is the square
  # `{x, y, size}` around the face in its 624x624 artwork.
  @default [
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

  # Representative monsters of the popular decks of each format (see the moduledoc).
  @extra [
    %{
      slug: "blackwing-kalut-the-moon-shadow",
      name: "Blackwing - Kalut the Moon Shadow",
      password: 85_215_458,
      face: {185, 90, 270}
    },
    %{
      slug: "blackwing-bora-the-spear",
      name: "Blackwing - Bora the Spear",
      password: 49_003_716,
      face: {120, 100, 220}
    },
    %{
      slug: "blackwing-armor-master",
      name: "Blackwing Armor Master",
      password: 69_031_175,
      face: {180, 20, 250}
    },
    %{
      slug: "elemental-hero-absolute-zero",
      name: "Elemental HERO Absolute Zero",
      password: 40_854_197,
      face: {195, 140, 190}
    },
    %{slug: "substitoad", name: "Substitoad", password: 20_663_556, face: {235, 30, 220}},
    %{
      slug: "gladiator-beast-laquari",
      name: "Gladiator Beast Laquari",
      password: 78_868_776,
      face: {175, 50, 230}
    },
    %{
      slug: "gladiator-beast-gyzarus",
      name: "Gladiator Beast Gyzarus",
      password: 48_156_348,
      face: {195, 25, 230}
    },
    %{
      slug: "lumina-lightsworn-summoner",
      name: "Lumina, Lightsworn Summoner",
      password: 95_503_687,
      face: {190, 30, 200}
    },
    %{
      slug: "judgment-dragon",
      name: "Judgment Dragon",
      password: 57_774_843,
      face: {155, 0, 180}
    },
    %{
      slug: "wulf-lightsworn-beast",
      name: "Wulf, Lightsworn Beast",
      password: 58_996_430,
      face: {100, 0, 230}
    },
    %{
      slug: "raiza-the-storm-monarch",
      name: "Raiza the Storm Monarch",
      password: 73_125_233,
      face: {240, 0, 140}
    },
    %{
      slug: "dekoichi-the-battlechanted-locomotive",
      name: "Dekoichi the Battlechanted Locomotive",
      password: 87_621_407,
      face: {210, 65, 220}
    },
    %{slug: "chaos-sorcerer", name: "Chaos Sorcerer", password: 9_596_126, face: {220, 90, 170}},
    %{slug: "thunder-dragon", name: "Thunder Dragon", password: 31_786_629, face: {80, 5, 220}},
    %{slug: "blade-knight", name: "Blade Knight", password: 39_507_162, face: {355, 160, 170}},
    %{slug: "don-zaloog", name: "Don Zaloog", password: 76_922_029, face: {210, 20, 230}},
    %{slug: "tsukuyomi", name: "Tsukuyomi", password: 34_853_266, face: {360, 25, 200}},
    %{
      slug: "thousand-eyes-restrict",
      name: "Thousand-Eyes Restrict",
      password: 63_519_819,
      face: {165, 135, 215}
    },
    %{
      slug: "zaborg-the-thunder-monarch",
      name: "Zaborg the Thunder Monarch",
      password: 51_945_556,
      face: {178, 25, 190}
    },
    %{
      slug: "gyaku-gire-panda",
      name: "Gyaku-Gire Panda",
      password: 9_817_927,
      face: {60, 20, 260}
    },
    %{
      slug: "injection-fairy-lily",
      name: "Injection Fairy Lily",
      password: 79_575_620,
      face: {260, 55, 230}
    },
    %{slug: "d-d-assailant", name: "D.D. Assailant", password: 70_074_904, face: {140, 60, 190}},
    %{slug: "gigantes", name: "Gigantes", password: 47_606_319, face: {190, 50, 200}},
    %{
      slug: "goblin-attack-force",
      name: "Goblin Attack Force",
      password: 78_658_564,
      face: {10, 150, 200}
    },
    %{
      slug: "the-agent-of-mystery-earth",
      name: "The Agent of Mystery - Earth",
      password: 91_188_343,
      face: {280, 120, 190}
    },
    %{
      slug: "master-hyperion",
      name: "Master Hyperion",
      password: 55_794_644,
      face: {190, 50, 230}
    },
    %{
      slug: "gachi-gachi-gantetsu",
      name: "Gachi Gachi Gantetsu",
      password: 10_002_346,
      face: {285, 30, 170}
    },
    %{slug: "reborn-tengu", name: "Reborn Tengu", password: 10_028_593, face: {202, 50, 220}},
    %{
      slug: "trishula-dragon-of-the-ice-barrier",
      name: "Trishula, Dragon of the Ice Barrier",
      password: 52_687_916,
      face: {200, 10, 200}
    },
    %{slug: "spore", name: "Spore", password: 11_747_708, face: {120, 60, 360}},
    %{
      slug: "the-fabled-catsith",
      name: "The Fabled Catsith",
      password: 56_399_890,
      face: {210, 195, 220}
    },
    %{slug: "fabled-kushano", name: "Fabled Kushano", password: 97_439_806, face: {195, 20, 240}},
    %{
      slug: "elemental-hero-neos-alius",
      name: "Elemental HERO Neos Alius",
      password: 69_884_162,
      face: {110, 60, 220}
    },
    %{
      slug: "elemental-hero-the-shining",
      name: "Elemental HERO The Shining",
      password: 22_061_412,
      face: {225, 115, 170}
    },
    %{slug: "t-g-warwolf", name: "T.G. Warwolf", password: 293_542, face: {120, 90, 180}},
    %{
      slug: "t-g-rush-rhino",
      name: "T.G. Rush Rhino",
      password: 36_687_247,
      face: {100, 130, 220}
    },
    %{slug: "scrap-beast", name: "Scrap Beast", password: 19_139_516, face: {110, 140, 280}},
    %{slug: "scrap-dragon", name: "Scrap Dragon", password: 76_774_528, face: {220, 230, 180}}
  ]

  @sets %{
    ~D[2010-04-24] =>
      ~w(blackwing-kalut-the-moon-shadow blackwing-shura-the-blue-flame blackwing-bora-the-spear blackwing-vayu-the-emblem-of-honor blackwing-armor-master dark-grepher elemental-hero-stratos elemental-hero-absolute-zero substitoad gladiator-beast-laquari gladiator-beast-gyzarus lumina-lightsworn-summoner judgment-dragon wulf-lightsworn-beast caius-the-shadow-monarch raiza-the-storm-monarch),
    ~D[2005-04-01] =>
      ~w(dekoichi-the-battlechanted-locomotive chaos-sorcerer thunder-dragon blade-knight don-zaloog tsukuyomi thousand-eyes-restrict zaborg-the-thunder-monarch gyaku-gire-panda injection-fairy-lily d-d-assailant gigantes goblin-attack-force),
    ~D[2011-09-01] =>
      ~w(the-agent-of-mystery-earth master-hyperion gachi-gachi-gantetsu reborn-tengu trishula-dragon-of-the-ice-barrier spore the-fabled-catsith chaos-sorcerer fabled-kushano elemental-hero-neos-alius elemental-hero-the-shining t-g-warwolf t-g-rush-rhino scrap-beast scrap-dragon)
  }

  # As many as the most players of a game (`Game.max_players/0`).
  @min_cards 4

  @pool @default ++ @extra
  @slugs Enum.map(@pool, & &1.slug)
  @default_slugs Enum.map(@default, & &1.slug)

  @doc "Every monster of every set: `%{slug, name, password, face}`."
  def all, do: @pool

  @doc "How many cards a format's own list needs before games use it."
  def min_cards, do: @min_cards

  @doc "The slugs of the default pool: what a format without a set of its own uses."
  def default_slugs, do: @default_slugs

  @doc """
  The slugs a game of the format with this `date` picks its pictures from: the
  format's own set (Edison 2010-04-24, Goat 2005-04-01, Tengu 2011-09-01), else
  the default pool. The date is used because it is fixed when a format is
  created, while the name can be edited: renaming a format keeps its set.
  """
  def for_format(%Date{} = date), do: Map.get(@sets, date, @default_slugs)

  def for_format(_), do: @default_slugs

  @doc """
  The slugs a game of this format picks from: the cards in its `avatar_cards`
  (a loaded list of structs with a `card_id`, as `Quiz.get_format!/1`
  preloads it) as card slugs, in order, once there are enough of them for the
  most players of a game (`min_cards/0`); else `for_format/1` of its date. An
  unloaded, empty or too short list means the date's set, so that no game is
  left without a different picture for every player.
  """
  def pool(%{avatar_cards: links}) when is_list(links) and length(links) >= @min_cards,
    do: Enum.map(links, &card_slug(&1.card_id))

  def pool(%{date: date}), do: for_format(date)
  def pool(_), do: @default_slugs

  @doc """
  `count` different slugs out of `pool` (default: the default pool), chosen
  with `shuffle` (as in `Game.new/4`). With more players than monsters they
  repeat.

  `chosen` has one entry per player, a slug or nil: those players get their
  slug, the others get different ones out of the pool without the chosen
  (the pool again if nothing else is left). Missing entries count as nil.
  """
  def assign(count, shuffle \\ &Enum.shuffle/1, pool \\ @default_slugs, chosen \\ [])
      when is_integer(count) and count >= 0 do
    chosen =
      chosen |> Enum.take(count) |> Enum.concat(List.duplicate(nil, count)) |> Enum.take(count)

    taken = Enum.reject(chosen, &is_nil/1)

    free =
      case pool -- taken do
        [] -> pool
        rest -> rest
      end

    if free == [] do
      chosen
    else
      {result, _} =
        Enum.map_reduce(chosen, free |> shuffle.() |> Stream.cycle(), fn
          nil, rest -> {Enum.at(rest, 0), Stream.drop(rest, 1)}
          slug, rest -> {slug, rest}
        end)

      result
    end
  end

  @doc "The slug of the pool card with this database id."
  def card_slug(id) when is_integer(id) and id in 1..@max_card_id, do: "card-#{id}"

  @doc "The database id in a card slug, else nil (`\"card-007\"`, `\"card-\"`, huge ids are no slugs)."
  def card_id(slug) when is_binary(slug) do
    with [_, digits] <- Regex.run(~r/\Acard-([1-9][0-9]*)\z/, slug),
         id when id <= @max_card_id <- String.to_integer(digits) do
      id
    else
      _ -> nil
    end
  end

  def card_id(_), do: nil

  @doc """
  The image path of `slug`: the card's artwork for a card slug (the controller
  serves widths 200 and 400; CSS squares it), the cropped file for a monster of
  the pool, nil for nil or anything else.
  """
  def path(slug, width \\ 200)

  def path(slug, _width) when slug in @slugs, do: "/images/avatars/#{slug}.jpg"

  def path(slug, width) when width in [200, 400] do
    if id = card_id(slug), do: "/cards/#{id}/artwork?w=#{width}"
  end

  def path(slug, _width), do: path(slug, 200)

  @doc """
  The crop of a card picture that has none stored: the focus point in the
  centre of the artwork (`x`, `y` in percent, 0..100) at a zoom of 150
  percent (100..300).
  """
  def default_crop, do: %{x: 50, y: 50, zoom: 150}

  @doc """
  Where to put the artwork of a crop inside its (square) container, all in
  percent of the container: the image is `size` (the zoom) wide and high and
  sits at `left`, `top` (zero or negative) so that the focus point lands in the
  middle of the container. The image is kept covering the container, so a
  focus point near an edge is moved inwards as far as needed:
  `left = clamp(50 - x * zoom / 100, 100 - zoom, 0)`, the same for `top`.

      iex> MillenniumQuiz.Avatars.crop_box(%{x: 50, y: 50, zoom: 150})
      %{size: 150.0, left: -25.0, top: -25.0}
  """
  def crop_box(%{x: x, y: y, zoom: zoom}) do
    %{size: zoom * 1.0, left: offset(x, zoom), top: offset(y, zoom)}
  end

  defp offset(focus, zoom) do
    (50 - focus * zoom / 100) |> max(100 - zoom) |> min(0) |> Kernel.*(1.0)
  end

  @doc "The monster's name, or nil for an unknown slug and for a card slug (no database here)."
  def name(slug), do: Enum.find_value(@pool, &(&1.slug == slug && &1.name))
end
