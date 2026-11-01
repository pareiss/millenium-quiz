# Content for bin/layout-test: a format whose questions have 4, 3 and 1 cards.
# The cards are inserted directly (no network, no artwork), so it works in CI.
# mix run priv/repo/layout_fixture.exs (or LAYOUT_FIXTURE=1 with
# Release.seed_layout_fixture() in a release). Running it twice does nothing, the format name is unique.
alias MillenniumQuiz.Cards.Card
alias MillenniumQuiz.{Quiz, Repo}
alias MillenniumQuiz.Quiz.Format

if Repo.get_by(Format, name: "Layout check") do
  IO.puts("Layout fixture already exists, skipping.")
else
  cards =
    for n <- 1..4 do
      Repo.get_by(Card, password: 990_000 + n) ||
        Repo.insert!(%Card{
          name: "Layout Card #{n}",
          password: 990_000 + n,
          kind: "Monster",
          frame_type: "normal",
          attribute: "DARK",
          level: 4,
          atk: "1800",
          def: "1200",
          monster_type_line: "Warrior / Normal",
          fetched_at: DateTime.utc_now(:second)
        })
    end

  {:ok, format} =
    Quiz.create_format(%{
      "name" => "Layout check",
      "date" => Date.utc_today(),
      "description" => "Fixture for bin/layout-test: questions with 4, 3 and 1 cards, the first two cards of each owned by player 1 and 2.",
      "topics" => %{"0" => %{"name" => "Four cards"}, "1" => %{"name" => "Fewer cards"}}
    })

  [four, fewer] = format.topics

  choices = %{
    "0" => %{"text" => "The first", "correct" => "true"},
    "1" => %{"text" => "{P2} is second"},
    "2" => %{"text" => "The third"},
    "3" => %{"text" => "The fourth"}
  }

  # the first question of the board has 4 cards (bin/layout-test picks it)
  for {topic, text, count} <- [
        {four, "{P1} and {P2} look at four cards: is [Layout Card 1] or [Layout Card 2] the first?", 4},
        {fewer, "Which of these three cards is the first?", 3},
        {fewer, "What does this card look like?", 1}
      ] do
    {:ok, _} =
      Quiz.create_question(
        topic,
        %{"text" => text, "choices" => choices},
        # the first two cards belong to player 1 and player 2
        cards |> Enum.take(count) |> Enum.with_index() |> Enum.map(fn {card, i} -> {card.id, if(i < 2, do: i + 1)} end)
      )
  end

  IO.puts("Seeded format #{format.name}.")
end

# A second format whose admin list of profile pictures is made of five cards with a
# (generated, solid colour) artwork, so that the pictures of cards load without a network.
if Repo.get_by(Format, name: "Layout check pictures") do
  IO.puts("Layout picture fixture already exists, skipping.")
else
  alias MillenniumQuiz.Cards.CardArtwork

  pictures =
    for n <- 1..5 do
      card =
        Repo.get_by(Card, password: 991_000 + n) ||
          Repo.insert!(%Card{
            name: "Layout Picture #{n}",
            password: 991_000 + n,
            kind: "Monster",
            frame_type: "normal",
            attribute: "LIGHT",
            level: 4,
            atk: "1000",
            def: "1000",
            monster_type_line: "Warrior / Normal",
            fetched_at: DateTime.utc_now(:second)
          })

      unless Repo.get_by(CardArtwork, card_id: card.id) do
        {:ok, image} = Vix.Vips.Operation.black(160, 160)
        {:ok, image} = Vix.Vips.Operation.linear(image, [1, 1, 1], [40 * n, 255 - 40 * n, 128])
        {:ok, jpeg} = Vix.Vips.Image.write_to_buffer(image, ".jpg")

        Repo.insert!(%CardArtwork{
          card_id: card.id,
          artwork_id: 991_000 + n,
          content_type: "image/jpeg",
          data: jpeg,
          source_url: "https://example.invalid/layout-picture-#{n}.jpg",
          fetched_at: DateTime.utc_now(:second)
        })
      end

      card
    end

  {:ok, format} =
    Quiz.create_format(%{
      "name" => "Layout check pictures",
      "date" => Date.utc_today(),
      "description" => "Fixture for bin/layout-test: five cards as the format's profile pictures.",
      "topics" => %{"0" => %{"name" => "Pictures"}, "1" => %{"name" => "More pictures"}}
    })

  for card <- pictures, do: {:ok, _} = Quiz.add_avatar_card(format.id, card.id)

  # a format is only listed (and playable) with questions
  for topic <- format.topics do
    {:ok, _} =
      Quiz.create_question(
        topic,
        %{
          "text" => "Which picture is the first?",
          "choices" => %{
            "0" => %{"text" => "The first", "correct" => "true"},
            "1" => %{"text" => "The second"}
          }
        },
        []
      )
  end

  IO.puts("Seeded format #{format.name}.")
end

# A third format for the life-point duel: 2 topics of 6 questions, so the last ones cost 2500 and
# 3000 life points and two wrong answers knock a player out of 4000. Its name must not contain
# "Layout check" (bin/layout-test finds the other fixtures by that).
if Repo.get_by(Format, name: "LP duel fixture") do
  IO.puts("LP duel fixture already exists, skipping.")
else
  {:ok, format} =
    Quiz.create_format(%{
      "name" => "LP duel fixture",
      "date" => Date.utc_today(),
      "description" => "Fixture for bin/layout-test: 2 topics of 6 questions (100 up to 3000 damage).",
      "topics" => %{"0" => %{"name" => "First duel topic"}, "1" => %{"name" => "Second duel topic"}}
    })

  for topic <- format.topics, n <- 1..6 do
    {:ok, _} =
      Quiz.create_question(
        topic,
        %{
          "text" => "Duel question #{n}?",
          "choices" => %{
            "0" => %{"text" => "Right", "correct" => "true"},
            "1" => %{"text" => "Wrong"}
          }
        },
        []
      )
  end

  IO.puts("Seeded format #{format.name}.")
end

# A fourth format for the board in the game (docs: Game, GameLive): the first question of the first topic
# has a board (Master Rule 4 by the date: both Extra Monster Zones, a hand, graveyards, a face-down card of
# each player); the others have none. The name must not contain "Layout check".
if Repo.get_by(Format, name: "Board in game fixture") do
  IO.puts("Board in game fixture already exists, skipping.")
else
  alias MillenniumQuiz.Quiz.Board

  text =
    "Once per turn, during your Main Phase: you can target 1 monster in your GY; Special Summon it, " <>
      "but it cannot attack this turn. If this card is destroyed by battle or card effect, you can " <>
      "add 1 card from your Deck to your hand. You can only use each effect of this card's name once per turn."

  # {password, name, frame_type, kind, atk, def, level}
  specs = [
    {992_001, "Board Dragon", "effect", "Monster", "2500", "2000", 7},
    {992_002, "Board Knight", "normal", "Monster", "1800", "1200", 4},
    {992_003, "Board Mage", "effect", "Monster", "1200", "800", 3},
    {992_004, "Board Hole", "trap", "Trap", nil, nil, nil},
    {992_005, "Board Storm", "spell", "Spell", nil, nil, nil},
    {992_006, "Board Field", "spell", "Spell", nil, nil, nil},
    {992_007, "Board Fusion", "fusion", "Monster", "2800", "2000", 8},
    {992_008, "Board Link", "link", "Monster", "2300", nil, nil},
    {992_009, "Board Xyz", "xyz", "Monster", "2500", "2000", nil},
    {992_010, "Board Draw", "spell", "Spell", nil, nil, nil},
    {992_011, "Board Gate", "trap", "Trap", nil, nil, nil},
    {992_012, "Board Ghost", "effect", "Monster", "400", "1600", 3}
  ]

  for {password, name, frame, kind, atk, def, level} <- specs do
    Repo.get_by(Card, password: password) ||
      Repo.insert!(%Card{
        name: name,
        password: password,
        kind: kind,
        frame_type: frame,
        attribute: if(kind == "Monster", do: "DARK"),
        monster_type_line: if(kind == "Monster", do: "Warrior / Effect"),
        level: level,
        rank: if(frame == "xyz", do: 4),
        atk: atk,
        def: def,
        texts: %{"en" => text},
        fetched_at: DateTime.utc_now(:second)
      })
  end

  c = fn code, pos -> %{"code" => code, "pos" => pos} end

  {:ok, board} =
    Board.cast(%{
      "v" => 1,
      "turn" => 3,
      "phase" => "main1",
      "turnPlayer" => 1,
      "emz" => [c.(992_008, "atk"), Map.put(c.(992_009, "atk"), "overlay", [992_001, 992_002])],
      "players" => [
        %{
          "lp" => 6200,
          "monsters" => [nil, c.(992_001, "atk"), c.(992_002, "def"), c.(992_003, "set"), nil],
          "spells" => [nil, c.(992_004, "set"), nil, c.(992_005, "set"), nil],
          "field" => c.(992_006, "atk"),
          "hand" => [c.(992_010, "atk"), c.(992_011, "atk")],
          "grave" => [c.(992_012, "atk"), c.(992_002, "atk")],
          "extra" => [c.(992_007, "atk")],
          "deck" => 25
        },
        %{
          "lp" => 4500,
          "monsters" => [c.(992_002, "atk"), nil, c.(992_003, "set"), nil, c.(992_001, "def")],
          "spells" => [c.(992_004, "set"), nil, nil, nil, nil],
          "grave" => [c.(992_012, "atk")],
          "deck" => 22
        }
      ]
    })

  {:ok, format} =
    Quiz.create_format(%{
      "name" => "Board in game fixture",
      "date" => Date.utc_today(),
      "description" => "Fixture for bin/layout-test: the first question has a board, the others none.",
      "topics" => %{"0" => %{"name" => "With a board"}, "1" => %{"name" => "Without"}}
    })

  [with_board, without] = format.topics

  choices = %{
    "0" => %{"text" => "Attack with the dragon", "correct" => "true"},
    "1" => %{"text" => "Set a card and pass"},
    "2" => %{"text" => "Summon the link monster"}
  }

  {:ok, question} =
    Quiz.create_question(
      with_board,
      %{"text" => "{P1} has this board in Main Phase 1. What is the best next play?", "choices" => choices},
      []
    )

  question |> Ecto.Changeset.change(board: board) |> Repo.update!()

  for {topic, text} <- [{with_board, "A second question, without a board?"}, {without, "A third one?"}] do
    {:ok, _} = Quiz.create_question(topic, %{"text" => text, "choices" => choices}, [])
  end

  IO.puts("Seeded format #{format.name}.")
end
