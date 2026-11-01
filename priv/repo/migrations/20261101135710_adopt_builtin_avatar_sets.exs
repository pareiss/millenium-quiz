defmodule MillenniumQuiz.Repo.Migrations.AdoptBuiltinAvatarSets do
  use Ecto.Migration

  # Moves the built-in profile-picture sets of Edison (2010-04-24), Goat
  # (2005-04-01) and Tengu (2011-09-01) into `format_avatar_cards` and
  # `card_avatar_crops`, so that admins own them.
  #
  # What it does, per set, only when ALL of these hold:
  #   * a format with the set's date exists and has no profile-picture cards
  #     yet (an admin's own list is never touched, running it twice is a no-op),
  #   * every card of the set is already in the card pool, by password, and was
  #     released by the format's date.
  # Then it inserts the links in the set's order and a crop per card that has
  # none. Otherwise it changes nothing: the format keeps using the built-in set
  # in code (`Avatars.for_format/1`), exactly as before. A migration cannot
  # fetch cards from the network, so a pool that lacks cards (an empty one, or
  # a database whose questions use other cards) is completed with
  # `MillenniumQuiz.Release.adopt_avatar_sets/0`, which fetches them one at a
  # time and links the sets the same way.
  #
  # The data is a frozen copy of `Avatars.set_for/1` and `Avatars.face_crop/1`
  # of 2026-11-01 (a migration must not follow later edits of that module):
  # {password, crop x, crop y, crop zoom}, in display order. At most 44 links
  # and 43 crops (Chaos Sorcerer is in two sets) are written; no card is.
  #
  # `down` does nothing: the rows cannot be told apart from an admin's own
  # choices made since, and the code falls back to the built-in sets for a
  # format whose list has fewer than 4 cards, so leaving them is harmless.

  @sets [
    {"2005-04-01",
     [
       {87_621_407, 51, 28, 284},
       {9_596_126, 49, 28, 300},
       {31_786_629, 30, 18, 284},
       {39_507_162, 71, 39, 300},
       {76_922_029, 52, 22, 271},
       {34_853_266, 74, 20, 300},
       {63_519_819, 44, 39, 290},
       {51_945_556, 44, 19, 300},
       {9_817_927, 30, 24, 240},
       {79_575_620, 60, 27, 271},
       {70_074_904, 38, 25, 300},
       {47_606_319, 46, 24, 300},
       {78_658_564, 18, 40, 300}
     ]},
    {"2010-04-24",
     [
       {85_215_458, 51, 36, 231},
       {58_820_853, 44, 22, 300},
       {49_003_716, 37, 34, 284},
       {72_714_392, 49, 32, 271},
       {69_031_175, 49, 23, 250},
       {14_536_035, 55, 16, 300},
       {40_044_918, 37, 22, 300},
       {40_854_197, 46, 38, 300},
       {20_663_556, 55, 22, 284},
       {78_868_776, 46, 26, 271},
       {48_156_348, 50, 22, 271},
       {95_503_687, 46, 21, 300},
       {57_774_843, 39, 16, 300},
       {58_996_430, 34, 18, 271},
       {9_748_752, 49, 18, 300},
       {73_125_233, 50, 16, 300}
     ]},
    {"2011-09-01",
     [
       {91_188_343, 60, 34, 300},
       {55_794_644, 49, 26, 271},
       {10_002_346, 59, 18, 300},
       {10_028_593, 50, 26, 284},
       {52_687_916, 48, 18, 300},
       {11_747_708, 48, 38, 173},
       {56_399_890, 51, 49, 284},
       {9_596_126, 49, 28, 300},
       {97_439_806, 50, 22, 260},
       {69_884_162, 35, 27, 284},
       {22_061_412, 50, 32, 300},
       {293_542, 34, 29, 300},
       {36_687_247, 34, 38, 284},
       {19_139_516, 40, 45, 223},
       {76_774_528, 50, 51, 300}
     ]}
  ]

  def up do
    for {date, cards} <- @sets do
      date = Date.from_iso8601!(date)

      %{rows: formats} =
        repo().query!(
          """
          SELECT id FROM formats
          WHERE date = $1
            AND NOT EXISTS (SELECT 1 FROM format_avatar_cards WHERE format_id = formats.id)
          """,
          [date]
        )

      if formats != [] do
        passwords = Enum.map(cards, &elem(&1, 0))

        %{rows: rows} =
          repo().query!(
            """
            SELECT password, id FROM cards
            WHERE password = ANY($1)
              AND (tcg_release_date IS NULL OR tcg_release_date <= $2)
            """,
            [passwords, date]
          )

        ids = Map.new(rows, fn [password, id] -> {password, id} end)

        if map_size(ids) == length(Enum.uniq(passwords)) do
          for [format_id] <- formats, do: link(format_id, cards, ids)
          crop(cards, ids)
        end
      end
    end

    :ok
  end

  def down, do: :ok

  defp link(format_id, cards, ids) do
    cards
    |> Enum.with_index()
    |> Enum.each(fn {{password, _x, _y, _zoom}, position} ->
      repo().query!(
        """
        INSERT INTO format_avatar_cards (format_id, card_id, position)
        VALUES ($1, $2, $3) ON CONFLICT (format_id, card_id) DO NOTHING
        """,
        [format_id, Map.fetch!(ids, password), position]
      )
    end)
  end

  # a crop an admin already stored for the card wins
  defp crop(cards, ids) do
    Enum.each(cards, fn {password, x, y, zoom} ->
      repo().query!(
        """
        INSERT INTO card_avatar_crops (card_id, x, y, zoom)
        VALUES ($1, $2, $3, $4) ON CONFLICT (card_id) DO NOTHING
        """,
        [Map.fetch!(ids, password), x, y, zoom]
      )
    end)
  end
end
