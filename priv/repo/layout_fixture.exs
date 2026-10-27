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
      "description" => "Fixture for bin/layout-test: questions with 4, 3 and 1 cards.",
      "topics" => %{"0" => %{"name" => "Four cards"}, "1" => %{"name" => "Fewer cards"}}
    })

  [four, fewer] = format.topics

  choices = %{
    "0" => %{"text" => "The first", "correct" => "true"},
    "1" => %{"text" => "The second"},
    "2" => %{"text" => "The third"},
    "3" => %{"text" => "The fourth"}
  }

  # the first question of the board has 4 cards (bin/layout-test picks it)
  for {topic, text, count} <- [
        {four, "Which of these four cards is the first?", 4},
        {fewer, "Which of these three cards is the first?", 3},
        {fewer, "What does this card look like?", 1}
      ] do
    {:ok, _} =
      Quiz.create_question(
        topic,
        %{"text" => text, "choices" => choices},
        cards |> Enum.take(count) |> Enum.map(& &1.id)
      )
  end

  IO.puts("Seeded format #{format.name}.")
end
