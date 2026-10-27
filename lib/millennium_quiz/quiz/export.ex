defmodule MillenniumQuiz.Quiz.Export do
  @moduledoc """
  A portable backup of the author-written quiz content: formats, topics,
  questions, choices and the card links of each question.

  Not included: games, accounts and the card pool. A card link carries the
  card's YGOPRODeck id (`password`, what `Cards.import/1` takes) and its name,
  never a database id, so the file can be restored into any database.

  The order is stable (formats by name, everything else by position), so two
  exports of the same data are identical apart from `exported_at`. The list
  order is the position: topics and questions get their positions back from
  their place in the list.

  ## Shape

      %{
        "version" => 1,
        "exported_at" => "2026-10-24T12:00:00Z",
        "formats" => [
          %{
            "name" => "Edison",
            "description" => nil,
            "date" => "2010-03-01",
            "topics" => [
              %{
                "name" => "Monsters",
                "questions" => [
                  %{
                    "text" => "What does [Monster Reborn] do?",
                    "points" => nil,
                    "submitted_by" => nil,
                    "choices" => [%{"text" => "...", "correct" => true}],
                    "cards" => [%{"password" => 83764718, "name" => "Monster Reborn"}]
                  }
                ]
              }
            ]
          }
        ]
      }

  A card has an `"owner"` (1 or 2, the player it belongs to in the question)
  only when a player owns it. The format stays version 1: a backup without
  owners imports as before, with no card owned.
  """
  import Ecto.Query

  alias MillenniumQuiz.Repo
  alias MillenniumQuiz.Quiz.{Format, Question, QuestionCard, Topic}

  @version 1

  def version, do: @version

  @doc "The backup as a JSON-able map."
  def build do
    %{
      "version" => @version,
      "exported_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "formats" => Enum.map(load_formats(), &format/1)
    }
  end

  @doc "The backup as pretty-printed JSON."
  def to_json, do: build() |> Jason.encode!(pretty: true)

  defp load_formats do
    questions = from q in Question, order_by: [asc: q.position, asc: q.id]
    topics = from t in Topic, order_by: [asc: t.position, asc: t.id]
    links = from qc in QuestionCard, order_by: [asc: qc.position, asc: qc.id]

    Repo.all(
      from f in Format,
        order_by: [asc: f.name, asc: f.id],
        preload: [
          topics: ^{topics, [questions: {questions, [question_cards: {links, :card}]}]}
        ]
    )
  end

  defp format(f) do
    %{
      "name" => f.name,
      "description" => f.description,
      "date" => Date.to_iso8601(f.date),
      "topics" => Enum.map(f.topics, &topic/1)
    }
  end

  defp topic(t), do: %{"name" => t.name, "questions" => Enum.map(t.questions, &question/1)}

  defp question(q) do
    %{
      "text" => q.text,
      "points" => q.points,
      "submitted_by" => q.submitted_by,
      "choices" => Enum.map(q.choices, &%{"text" => &1.text, "correct" => &1.correct}),
      "cards" => Enum.map(q.question_cards, &card/1)
    }
  end

  # "owner" only when a player owns the card, so a backup without owners is
  # the same as before they existed
  defp card(%{card: card, owner: owner}) do
    %{"password" => card.password, "name" => card.name}
    |> then(&if(owner, do: Map.put(&1, "owner", owner), else: &1))
  end
end
