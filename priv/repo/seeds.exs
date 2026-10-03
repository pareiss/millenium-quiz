# Sample content: mix run priv/repo/seeds.exs (or Release.seed() in a release).
# Running it twice does nothing, the format name is unique.
alias MillenniumQuiz.{Quiz, Repo}
alias MillenniumQuiz.Quiz.Format

if Repo.get_by(Format, name: "Duel Monsters Basics") do
  IO.puts("Seed format already exists, skipping.")
else
  {:ok, format} =
    Quiz.create_format(%{
      "name" => "Duel Monsters Basics",
      # timeless basics: card texts as they read today
      "date" => Date.utc_today(),
      "description" =>
        "Warm-up questions about the card game: monsters, spells & traps and the rules.",
      "topics" => %{
        "0" => %{"name" => "Monsters"},
        "1" => %{"name" => "Spells & Traps"},
        "2" => %{"name" => "Rules"}
      }
    })

  choices = fn correct, wrong ->
    [%{"text" => correct, "correct" => "true"} | Enum.map(wrong, &%{"text" => &1})]
    |> Enum.shuffle()
    |> Enum.with_index()
    |> Map.new(fn {c, i} -> {to_string(i), c} end)
  end

  questions = %{
    "Monsters" => [
      {"What is the ATK of Blue-Eyes White Dragon?", "3000", ["2500", "2800", "4000"]},
      {"What is the Attribute of Dark Magician?", "DARK", ["LIGHT", "EARTH", "WIND"]},
      {"How many pieces does Exodia the Forbidden One consist of?", "5", ["3", "4", "6"]}
    ],
    "Spells & Traps" => [
      {"What does Pot of Greed do?", "Draw 2 cards",
       ["Draw 1 card", "Gain 1000 LP", "Destroy 1 card"]},
      {"Which card destroys all monsters on the field?", "Dark Hole",
       ["Raigeki", "Monster Reborn", "Mirror Force"]},
      {"Which Trap destroys all of the opponent's Attack Position monsters when they attack?",
       "Mirror Force", ["Magic Cylinder", "Trap Hole", "Sakuretsu Armor"]}
    ],
    "Rules" => [
      {"How many Life Points does each player start with?", "8000", ["4000", "2000", "10000"]},
      {"How many cards does each player draw for the opening hand?", "5", ["4", "6", "7"]},
      {"What is the minimum number of cards in a Main Deck?", "40", ["30", "45", "60"]}
    ]
  }

  for topic <- format.topics, {text, correct, wrong} <- Map.fetch!(questions, topic.name) do
    {:ok, _} =
      Quiz.create_question(topic, %{"text" => text, "choices" => choices.(correct, wrong)})
  end

  IO.puts("Seeded format #{format.name}.")
end
