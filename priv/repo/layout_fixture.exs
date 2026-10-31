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
