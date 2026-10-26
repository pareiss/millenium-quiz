defmodule MillenniumQuiz.Quiz.SubmissionTest do
  use MillenniumQuiz.DataCase

  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.Quiz
  alias MillenniumQuiz.Quiz.Submission
  alias MillenniumQuiz.Repo

  defp attrs(extra \\ %{}) do
    Map.merge(
      %{"text" => "What does [Monster Reborn] do?", "choices" => choices_params()},
      extra
    )
  end

  setup do
    format = format_fixture()
    %{format: format, topic: hd(format.topics)}
  end

  test "stores a submission with a private token, pending", %{topic: topic} do
    {:ok, s} = Quiz.create_submission(topic, attrs(%{"submitter_name" => "  Yugi "}))
    assert s.status == "pending"
    assert s.submitter_name == "Yugi"
    assert byte_size(s.token) >= 20
    assert Quiz.get_submission_by_token(s.token).id == s.id
    assert Quiz.get_submission_by_token("nope") == nil
  end

  test "a blank name is stored as none, a long one is refused", %{topic: topic} do
    {:ok, s} = Quiz.create_submission(topic, attrs(%{"submitter_name" => "   "}))
    assert s.submitter_name == nil

    {:error, cs} =
      Quiz.create_submission(topic, attrs(%{"submitter_name" => String.duplicate("x", 31)}))

    assert %{submitter_name: [_]} = errors_on(cs)
  end

  test "needs 2-6 answers with exactly one correct", %{topic: topic} do
    assert {:error, cs} =
             Quiz.create_submission(topic, attrs(%{"choices" => choices_params(["a"])}))

    assert %{choices: [_]} = errors_on(cs)

    two_right = %{
      "0" => %{"text" => "a", "correct" => true},
      "1" => %{"text" => "b", "correct" => true}
    }

    assert {:error, cs} = Quiz.create_submission(topic, attrs(%{"choices" => two_right}))
    assert %{choices: [_]} = errors_on(cs)
  end

  test "refuses new submissions when too many are pending", %{topic: topic} do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      for i <- 1..Quiz.max_pending_submissions() do
        %{
          topic_id: topic.id,
          token: "t#{i}",
          text: "q",
          choices: [],
          status: "pending",
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(Submission, rows)
    assert {:error, :full} = Quiz.create_submission(topic, attrs())
  end

  test "approving creates a question and keeps the submission as written", %{topic: topic} do
    {:ok, s} = Quiz.create_submission(topic, attrs(%{"submitter_name" => "Yugi"}))

    edited = attrs(%{"text" => "Edited text?", "submitted_by" => "Yugi"})
    assert {:ok, question} = Quiz.approve_submission(s, topic, edited, [])

    assert question.submitted_by == "Yugi"
    assert question.text == "Edited text?"

    s = Quiz.get_submission(s.id)
    assert s.status == "approved"
    assert s.question_id == question.id
    assert s.text == "What does [Monster Reborn] do?"
    assert s.reviewed_at

    assert {:error, :reviewed} = Quiz.approve_submission(s, topic, edited, [])
    assert {:error, :reviewed} = Quiz.reject_submission(s)
  end

  test "an invalid approval leaves the submission pending", %{topic: topic} do
    {:ok, s} = Quiz.create_submission(topic, attrs())

    assert {:error, %Ecto.Changeset{}} =
             Quiz.approve_submission(s, topic, attrs(%{"text" => ""}), [])

    assert Quiz.get_submission(s.id).status == "pending"
  end

  test "rejecting keeps it; the question outlives deleting the submission", %{topic: topic} do
    {:ok, s} = Quiz.create_submission(topic, attrs())
    assert :ok = Quiz.reject_submission(s)
    assert Quiz.get_submission(s.id).status == "rejected"
    assert Quiz.count_submissions(:pending) == 0
    assert [%{id: id}] = Quiz.list_submissions(:rejected)
    assert id == s.id
  end

  test "the submitter name survives a backup; backups without it still import", %{topic: topic} do
    alias MillenniumQuiz.Quiz.{Export, Import}

    format_name = Repo.get!(MillenniumQuiz.Quiz.Format, topic.format_id).name
    question_fixture(topic, %{"submitted_by" => "Yugi"})
    data = Export.build()
    format = Enum.find(data["formats"], &(&1["name"] == format_name))
    assert [%{"submitted_by" => "Yugi"}] = hd(format["topics"])["questions"]

    Repo.delete!(Repo.get!(MillenniumQuiz.Quiz.Format, topic.format_id))
    assert {:ok, %{questions: 1}} = Import.run(%{"version" => 1, "formats" => [format]})
    assert Enum.any?(Repo.all(MillenniumQuiz.Quiz.Question), &(&1.submitted_by == "Yugi"))

    Repo.delete!(Repo.get_by!(MillenniumQuiz.Quiz.Format, name: format["name"]))

    old =
      update_in(format, ["topics"], fn ts ->
        for t <- ts,
            do:
              Map.update!(t, "questions", fn qs ->
                Enum.map(qs, &Map.delete(&1, "submitted_by"))
              end)
      end)

    assert {:ok, %{questions: 1}} = Import.run(%{"version" => 1, "formats" => [old]})
  end
end
