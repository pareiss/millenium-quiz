defmodule MillenniumQuiz.Quiz do
  @moduledoc """
  Admin-managed quiz content: formats, their 2-6 topics and the
  difficulty-ordered questions of each topic.
  """

  import Ecto.Query, warn: false

  alias MillenniumQuiz.Repo
  alias MillenniumQuiz.Quiz.{Format, Topic, Question, Submission}

  ## Formats

  def list_formats do
    Repo.all(from f in Format, order_by: f.name, preload: [topics: :questions])
  end

  @doc "Formats that can be played: at least 2 topics and 1 question."
  def list_playable_formats do
    question_counts =
      from t in Topic,
        left_join: q in assoc(t, :questions),
        group_by: t.format_id,
        select: %{
          format_id: t.format_id,
          topics: count(t.id, :distinct),
          questions: count(q.id)
        }

    Repo.all(
      from f in Format,
        join: s in subquery(question_counts),
        on: s.format_id == f.id,
        where: s.topics >= ^Format.min_topics() and s.questions > 0,
        order_by: f.name,
        select: %{format: f, topics: s.topics, questions: s.questions}
    )
  end

  def get_format!(id) do
    Format
    |> Repo.get!(id)
    |> Repo.preload(topics: :questions)
  end

  def create_format(attrs) do
    %Format{topics: []}
    |> Format.changeset(attrs)
    |> Repo.insert()
  end

  def update_format(%Format{} = format, attrs) do
    format
    |> Format.changeset(attrs)
    |> Repo.update()
  end

  def delete_format(%Format{} = format), do: Repo.delete(format)

  def change_format(%Format{} = format, attrs \\ %{}) do
    Format.changeset(format, attrs)
  end

  ## Questions

  @doc "The question with this id (topic preloaded), or nil (also for ids that aren't valid)."
  def get_question(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} -> Question |> Repo.get(id) |> Repo.preload(:topic)
      :error -> nil
    end
  end

  def get_question!(id) do
    Question |> Repo.get!(id) |> Repo.preload([:topic, question_cards: [card: :card_texts]])
  end

  def get_topic!(id), do: Topic |> Repo.get!(id) |> Repo.preload(:format)

  @doc "Position a new question gets: the end of the list, i.e. the hardest."
  def next_question_position(%Topic{} = topic) do
    Repo.one(from q in Question, where: q.topic_id == ^topic.id, select: count(q.id))
  end

  @doc """
  Creates a question at the end of the topic. `cards` sets the cards the
  question is about, in display order: card pool ids, or `{id, owner}` with the
  owner 1, 2 or nil (see `Question.put_cards/2`).
  """
  def create_question(%Topic{} = topic, attrs, cards \\ []) do
    %Question{topic_id: topic.id, position: next_question_position(topic), question_cards: []}
    |> Question.changeset(attrs)
    |> Question.put_cards(cards)
    |> Repo.insert()
  end

  def update_question(%Question{} = question, attrs, cards \\ nil) do
    question
    |> Repo.preload(:question_cards)
    |> Question.changeset(attrs)
    |> then(&if(cards, do: Question.put_cards(&1, cards), else: &1))
    |> Repo.update()
  end

  def delete_question(%Question{} = question) do
    Repo.transaction(fn ->
      Repo.delete!(question)
      renumber_questions(question.topic_id)
    end)
  end

  def change_question(%Question{} = question, attrs \\ %{}) do
    Question.changeset(question, attrs)
  end

  @doc """
  Moves a question one step easier (`:up`) or harder (`:down`) by swapping
  it with its neighbour. Default points follow automatically.
  """
  def move_question(%Question{} = question, direction) when direction in [:up, :down] do
    Repo.transaction(fn ->
      ids =
        Repo.all(
          from q in Question,
            where: q.topic_id == ^question.topic_id,
            order_by: [asc: q.position, asc: q.id],
            select: q.id,
            lock: "FOR UPDATE"
        )

      index = Enum.find_index(ids, &(&1 == question.id))
      target = if direction == :up, do: index - 1, else: index + 1

      ids =
        if target in 0..(length(ids) - 1)//1 do
          ids
          |> List.replace_at(index, Enum.at(ids, target))
          |> List.replace_at(target, question.id)
        else
          ids
        end

      write_positions(ids)
    end)
  end

  defp renumber_questions(topic_id) do
    Repo.all(
      from q in Question,
        where: q.topic_id == ^topic_id,
        order_by: [asc: q.position, asc: q.id],
        select: q.id
    )
    |> write_positions()
  end

  defp write_positions(ids) do
    ids
    |> Enum.with_index()
    |> Enum.each(fn {id, position} ->
      Repo.update_all(from(q in Question, where: q.id == ^id), set: [position: position])
    end)
  end

  @doc "All questions of a format with their topic and cards, used to build a game."
  def questions_for_format(format_id) do
    Repo.all(
      from q in Question,
        join: t in assoc(q, :topic),
        where: t.format_id == ^format_id,
        preload: [topic: t, question_cards: [card: :card_texts]]
    )
  end

  ## Suggested questions

  # Unreviewed submissions that are kept; over it, new ones are refused so a
  # flood cannot fill the database.
  @max_pending_submissions 200

  def max_pending_submissions, do: @max_pending_submissions

  @doc "Formats with their topics, for the suggestion form's pickers."
  def list_formats_with_topics do
    Repo.all(from f in Format, order_by: f.name, preload: [:topics])
  end

  @doc """
  Stores a player's suggestion for `topic`. Returns `{:error, :full}` when
  `max_pending_submissions/0` are already waiting.
  """
  def create_submission(%Topic{} = topic, attrs) do
    if count_submissions(:pending) >= @max_pending_submissions do
      {:error, :full}
    else
      %Submission{topic_id: topic.id, token: new_token(), choices: []}
      |> Submission.changeset(attrs)
      |> Repo.insert()
    end
  end

  def change_submission(%Submission{} = submission, attrs \\ %{}),
    do: Submission.changeset(submission, attrs)

  defp new_token, do: :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

  def get_submission(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} -> Submission |> Repo.get(id) |> Repo.preload(topic: :format)
      :error -> nil
    end
  end

  @doc "The submission with this private token, or nil."
  def get_submission_by_token(token) when is_binary(token) do
    Submission |> Repo.get_by(token: token) |> Repo.preload(topic: :format)
  end

  @doc "Submissions with this status (or all with `:all`), oldest pending first, newest otherwise."
  def list_submissions(status) do
    base = from s in Submission, preload: [topic: :format]

    case status do
      :pending ->
        from s in base, where: s.status == "pending", order_by: [asc: s.inserted_at, asc: s.id]

      :all ->
        from s in base, order_by: [desc: s.inserted_at, desc: s.id]

      status ->
        from s in base,
          where: s.status == ^to_string(status),
          order_by: [desc: s.inserted_at, desc: s.id]
    end
    |> Repo.all()
  end

  def count_submissions(status) do
    Repo.one(from s in Submission, where: s.status == ^to_string(status), select: count(s.id))
  end

  @doc """
  Creates the question an admin made from a pending submission and marks the
  submission approved, in one transaction. A submission that was reviewed in
  the meantime (another admin) is refused with `{:error, :reviewed}`.
  """
  def approve_submission(%Submission{id: id}, %Topic{} = topic, attrs, cards) do
    Repo.transaction(fn ->
      submission = Repo.one!(from s in Submission, where: s.id == ^id, lock: "FOR UPDATE")

      if submission.status != "pending" do
        Repo.rollback(:reviewed)
      else
        case create_question(topic, attrs, cards) do
          {:ok, question} ->
            submission
            |> Ecto.Changeset.change(
              status: "approved",
              question_id: question.id,
              reviewed_at: now()
            )
            |> Repo.update!()

            question

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end
    end)
  end

  @doc "Marks a pending submission rejected; it is kept."
  def reject_submission(%Submission{id: id}) do
    {count, _} =
      Repo.update_all(
        from(s in Submission, where: s.id == ^id and s.status == "pending"),
        set: [status: "rejected", reviewed_at: now()]
      )

    if count == 1, do: :ok, else: {:error, :reviewed}
  end

  def delete_submission(%Submission{} = submission), do: Repo.delete(submission)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
