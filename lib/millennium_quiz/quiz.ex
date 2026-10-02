defmodule MillenniumQuiz.Quiz do
  @moduledoc """
  Admin-managed quiz content: categories, their 2-6 topics and the
  difficulty-ordered questions of each topic.
  """

  import Ecto.Query, warn: false

  alias MillenniumQuiz.Repo
  alias MillenniumQuiz.Quiz.{Category, Topic, Question}

  ## Categories

  def list_categories do
    Repo.all(from c in Category, order_by: c.name, preload: [topics: :questions])
  end

  @doc "Categories that can be played: at least 2 topics and 1 question."
  def list_playable_categories do
    question_counts =
      from t in Topic,
        left_join: q in assoc(t, :questions),
        group_by: t.category_id,
        select: %{
          category_id: t.category_id,
          topics: count(t.id, :distinct),
          questions: count(q.id)
        }

    Repo.all(
      from c in Category,
        join: s in subquery(question_counts),
        on: s.category_id == c.id,
        where: s.topics >= ^Category.min_topics() and s.questions > 0,
        order_by: c.name,
        select: %{category: c, topics: s.topics, questions: s.questions}
    )
  end

  def get_category!(id) do
    Category
    |> Repo.get!(id)
    |> Repo.preload(topics: :questions)
  end

  def create_category(attrs) do
    %Category{topics: []}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  def delete_category(%Category{} = category), do: Repo.delete(category)

  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end

  ## Questions

  def get_question!(id), do: Question |> Repo.get!(id) |> Repo.preload(:topic)

  def get_topic!(id), do: Topic |> Repo.get!(id) |> Repo.preload(:category)

  @doc "Position a new question gets: the end of the list, i.e. the hardest."
  def next_question_position(%Topic{} = topic) do
    Repo.one(from q in Question, where: q.topic_id == ^topic.id, select: count(q.id))
  end

  @doc "Creates a question at the end of the topic."
  def create_question(%Topic{} = topic, attrs) do
    %Question{topic_id: topic.id, position: next_question_position(topic)}
    |> Question.changeset(attrs)
    |> Repo.insert()
  end

  def update_question(%Question{} = question, attrs) do
    question
    |> Question.changeset(attrs)
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

  @doc "All questions of a category with their topic, used to build a game."
  def questions_for_category(category_id) do
    Repo.all(
      from q in Question,
        join: t in assoc(q, :topic),
        where: t.category_id == ^category_id,
        preload: [topic: t]
    )
  end
end
