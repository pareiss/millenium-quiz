defmodule MillenniumQuiz.QuizTest do
  use MillenniumQuiz.DataCase, async: true

  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.Quiz
  alias MillenniumQuiz.Quiz.Question

  defp topics(n), do: Map.new(1..n//1, &{to_string(&1), %{"name" => "Topic #{&1}"}})

  describe "formats" do
    test "need between 2 and 6 topics" do
      assert {:error, cs} = Quiz.create_format(%{"name" => "One", "topics" => topics(1)})
      assert %{topics: ["must have between 2 and 6 topics"]} = errors_on(cs)

      assert {:error, cs} = Quiz.create_format(%{"name" => "None"})
      assert %{topics: [_]} = errors_on(cs)

      assert {:error, _} = Quiz.create_format(%{"name" => "Seven", "topics" => topics(7)})

      assert {:ok, _} =
               Quiz.create_format(%{
                 "name" => "Six",
                 "date" => "2005-04-01",
                 "topics" => topics(6)
               })
    end

    test "need a date" do
      assert {:error, cs} = Quiz.create_format(%{"name" => "Undated", "topics" => topics(2)})
      assert %{date: ["can't be blank"]} = errors_on(cs)
    end

    test "topics keep the form order as position" do
      format =
        format_fixture(%{"topics" => %{"0" => %{"name" => "B"}, "1" => %{"name" => "A"}}})

      assert Enum.map(format.topics, &{&1.name, &1.position}) == [{"B", 0}, {"A", 1}]
    end

    test "dropping a topic below the minimum is rejected" do
      format = format_fixture()

      attrs = %{
        "topics" => %{"0" => %{"id" => hd(format.topics).id, "name" => "x"}},
        "topics_drop" => ["1"]
      }

      assert {:error, cs} = Quiz.update_format(format, attrs)
      assert %{topics: [_]} = errors_on(cs)
    end

    test "only formats with questions are playable" do
      empty = format_fixture()
      playable = playable_format_fixture(1)

      ids = Enum.map(Quiz.list_playable_formats(), & &1.format.id)
      assert playable.id in ids
      refute empty.id in ids
    end
  end

  describe "questions" do
    setup do
      %{topic: hd(format_fixture().topics)}
    end

    test "need 2-6 answers with exactly one correct", %{topic: topic} do
      assert {:error, cs} =
               Quiz.create_question(topic, %{"text" => "?", "choices" => choices_params(["only"])})

      assert %{choices: [_]} = errors_on(cs)

      no_correct = choices_params(["a", "b"], -1)
      assert {:error, cs} = Quiz.create_question(topic, %{"text" => "?", "choices" => no_correct})
      assert %{choices: ["exactly one answer must be marked as correct"]} = errors_on(cs)
    end

    test "are appended and default points follow the position", %{topic: topic} do
      q1 = question_fixture(topic)
      q2 = question_fixture(topic)
      q3 = question_fixture(topic, %{"points" => 55})

      assert Enum.map([q1, q2, q3], & &1.position) == [0, 1, 2]
      assert Enum.map([q1, q2, q3], &Question.effective_points/1) == [10, 20, 55]
    end

    test "can be moved, which changes the default points", %{topic: topic} do
      q1 = question_fixture(topic)
      q2 = question_fixture(topic)

      {:ok, _} = Quiz.move_question(q2, :up)
      assert Quiz.get_question!(q2.id).position == 0
      assert Question.effective_points(Quiz.get_question!(q1.id)) == 20

      # moving past the edge is a no-op
      {:ok, _} = Quiz.move_question(Quiz.get_question!(q2.id), :up)
      assert Quiz.get_question!(q2.id).position == 0
    end

    test "deleting renumbers the rest", %{topic: topic} do
      q1 = question_fixture(topic)
      q2 = question_fixture(topic)
      {:ok, _} = Quiz.delete_question(q1)
      assert Quiz.get_question!(q2.id).position == 0
    end
  end
end
