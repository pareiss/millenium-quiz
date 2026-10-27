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
