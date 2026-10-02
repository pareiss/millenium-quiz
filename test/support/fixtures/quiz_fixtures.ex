defmodule MillenniumQuiz.QuizFixtures do
  alias MillenniumQuiz.Quiz

  def format_fixture(attrs \\ %{}) do
    {:ok, format} =
      attrs
      |> Enum.into(%{
        "name" => "Format #{System.unique_integer([:positive])}",
        "date" => "2005-04-01",
        "topics" => %{"0" => %{"name" => "Monsters"}, "1" => %{"name" => "Spells"}}
      })
      |> Quiz.create_format()

    Quiz.get_format!(format.id)
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

  @doc "A format with 2 topics and `per_topic` questions each; answer 0 is always right."
  def playable_format_fixture(per_topic \\ 2) do
    format = format_fixture()

    for topic <- format.topics, _ <- 1..per_topic do
      question_fixture(topic)
    end

    Quiz.get_format!(format.id)
  end
end
