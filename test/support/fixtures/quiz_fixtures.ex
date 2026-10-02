defmodule MillenniumQuiz.QuizFixtures do
  alias MillenniumQuiz.Quiz

  def category_fixture(attrs \\ %{}) do
    {:ok, category} =
      attrs
      |> Enum.into(%{
        "name" => "Category #{System.unique_integer([:positive])}",
        "topics" => %{"0" => %{"name" => "Monsters"}, "1" => %{"name" => "Spells"}}
      })
      |> Quiz.create_category()

    Quiz.get_category!(category.id)
  end

  @doc "Choices params with the answer at `correct` (default 0) being right."
  def choices_params(texts \\ ["Right", "Wrong 1", "Wrong 2"], correct \\ 0) do
    texts
    |> Enum.with_index()
    |> Map.new(fn {text, i} -> {to_string(i), %{"text" => text, "correct" => i == correct}} end)
  end

  def question_fixture(topic, attrs \\ %{}) do
    {:ok, question} =
      Quiz.create_question(
        topic,
        Enum.into(attrs, %{
          "text" => "Question #{System.unique_integer([:positive])}?",
          "choices" => choices_params()
        })
      )

    question
  end

  @doc "A category with 2 topics and `per_topic` questions each; answer 0 is always right."
  def playable_category_fixture(per_topic \\ 2) do
    category = category_fixture()

    for topic <- category.topics, _ <- 1..per_topic do
      question_fixture(topic)
    end

    Quiz.get_category!(category.id)
  end
end
