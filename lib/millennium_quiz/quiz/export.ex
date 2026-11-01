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
            "avatar_cards" => [%{"password" => 83764718, "name" => "Monster Reborn"}],
            "topics" => [
              %{
                "name" => "Monsters",
                "questions" => [
                  %{
                    "text" => "What does [Monster Reborn] do?",
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

  `"avatar_cards"` are the cards chosen as the format's profile pictures, in
  order, identified like the card links. A backup without the key imports
  with none (the format stays version 1).

  An avatar card has a `"crop"` (`{"x": 50, "y": 50, "zoom": 150}`, see
  `Quiz.set_avatar_crop/2`) only when a crop is stored for it. A backup
  without crops imports as before (the format stays version 1).

  A question has a `"board"` (the stored shape of `Quiz.Board`, codes only,
  including `"reveal_all"`) only when it has one. The format stays version 1:
  a backup without boards imports as before, and an importer from before
  boards simply ignores the key (a question comes back without its board).
  The import validates the board against the format's date, fetches cards the
  pool lacks, and restores the question without the board when that fails.

  A card has an `"owner"` (1 or 2, the player it belongs to in the question)
  only when a player owns it. The format stays version 1: a backup without
  owners imports as before, with no card owned.
  """
  import Ecto.Query

  alias MillenniumQuiz.Repo

  alias MillenniumQuiz.Quiz.{
    CardAvatarCrop,
    Format,
    FormatAvatarCard,
    Question,
    QuestionCard,
    Topic
  }

  @version 1

  def version, do: @version

  @doc "The backup as a JSON-able map."
  def build do
    crops = load_crops()

    %{
      "version" => @version,
      "exported_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "formats" => Enum.map(load_formats(), &format(&1, crops))
    }
  end

  @doc "The backup as pretty-printed JSON."
  def to_json, do: build() |> Jason.encode!(pretty: true)

  defp load_crops do
    Map.new(
      Repo.all(CardAvatarCrop),
      &{&1.card_id, %{"x" => &1.x, "y" => &1.y, "zoom" => &1.zoom}}
    )
  end

  defp avatar_card(link, crops) do
    %{"password" => link.card.password, "name" => link.card.name}
    |> then(&if(crop = crops[link.card_id], do: Map.put(&1, "crop", crop), else: &1))
  end

  defp load_formats do
    questions = from q in Question, order_by: [asc: q.position, asc: q.id]
    topics = from t in Topic, order_by: [asc: t.position, asc: t.id]
    avatars = from fa in FormatAvatarCard, order_by: [asc: fa.position, asc: fa.id]
    links = from qc in QuestionCard, order_by: [asc: qc.position, asc: qc.id]

    Repo.all(
      from f in Format,
        order_by: [asc: f.name, asc: f.id],
        preload: [
          avatar_cards: ^{avatars, :card},
          topics: ^{topics, [questions: {questions, [question_cards: {links, :card}]}]}
        ]
    )
  end

  defp format(f, crops) do
    %{
      "name" => f.name,
      "description" => f.description,
      "date" => Date.to_iso8601(f.date),
      "avatar_cards" => Enum.map(f.avatar_cards, &avatar_card(&1, crops)),
      "topics" => Enum.map(f.topics, &topic/1)
    }
  end

  defp topic(t), do: %{"name" => t.name, "questions" => Enum.map(t.questions, &question/1)}

  defp question(q) do
    %{
      "text" => q.text,
      "submitted_by" => q.submitted_by,
      "choices" => Enum.map(q.choices, &%{"text" => &1.text, "correct" => &1.correct}),
      "cards" => Enum.map(q.question_cards, &card/1)
    }
    |> then(&if(q.board, do: Map.put(&1, "board", q.board), else: &1))
  end

  # "owner" only when a player owns the card, so a backup without owners is
  # the same as before they existed
  defp card(%{card: card, owner: owner}) do
    %{"password" => card.password, "name" => card.name}
    |> then(&if(owner, do: Map.put(&1, "owner", owner), else: &1))
  end
end
