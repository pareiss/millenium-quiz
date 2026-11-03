defmodule MillenniumQuizWeb.QuestionExplanationTest do
  use MillenniumQuizWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import MillenniumQuiz.DataCase, only: [errors_on: 1]
  import Ecto.Query, only: [from: 2]
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{Game, Games, Quiz}
  alias MillenniumQuiz.Quiz.{Export, Import, Question}

  defp play_to_reveal(conn, format, names \\ ["Ann", "Bob"]) do
    {:ok, id} = Games.create_game(format.id, names, mode: :free)
    {:ok, view, _html} = live(conn, ~p"/games/#{id}")
    view |> element("#question-0") |> render_click()
    for _ <- names, do: view |> element("#choice-0") |> render_click()
    view
  end

  describe "the question" do
    test "an explanation is optional, a blank one is stored as none" do
      topic = hd(format_fixture().topics)

      none = question_fixture(topic)
      assert none.explanation == nil

      blank = question_fixture(topic, %{"explanation" => "   "})
      assert blank.explanation == nil

      kept = question_fixture(topic, %{"explanation" => "Because it says so."})
      assert Quiz.get_question!(kept.id).explanation == "Because it says so."
    end

    test "an explanation can be removed again" do
      question = question_fixture(hd(format_fixture().topics), %{"explanation" => "Why."})
      assert {:ok, q} = Quiz.update_question(question, %{"explanation" => ""})
      assert q.explanation == nil
    end

    test "an explanation longer than the limit is refused" do
      topic = hd(format_fixture().topics)

      assert {:error, cs} =
               Quiz.create_question(topic, %{
                 "text" => "Long?",
                 "choices" => choices_params(),
                 "explanation" => String.duplicate("x", Question.max_explanation_length() + 1)
               })

      assert %{explanation: [_]} = errors_on(cs)
    end
  end

  describe "the game snapshot" do
    test "keeps the explanation; older snapshots load without it" do
      format = format_fixture()
      question_fixture(hd(format.topics), %{"explanation" => "Because."})
      question_fixture(List.last(format.topics))

      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"], mode: :free)
      {:ok, %{game: game}} = Games.fetch_game(id)
      assert Enum.map(game.questions, & &1.explanation) |> Enum.sort() == [nil, "Because."]

      map = game |> Game.to_map() |> Jason.encode!() |> Jason.decode!()

      old =
        update_in(map, ["questions"], fn qs -> Enum.map(qs, &Map.delete(&1, "explanation")) end)

      assert Enum.all?(Game.from_map(old).questions, &(&1.explanation == nil))

      assert Enum.map(Game.from_map(map).questions, & &1.explanation) |> Enum.sort() == [
               nil,
               "Because."
             ]
    end
  end

  describe "backups" do
    setup do
      MillenniumQuiz.Repo.delete_all(Quiz.Format)
      :ok
    end

    test "the explanation survives an export and import; no key when there is none" do
      format = format_fixture(%{"name" => "Edison"})
      [monsters, spells] = format.topics
      question_fixture(monsters, %{"text" => "With?", "explanation" => "Line 1\nLine 2"})
      question_fixture(spells, %{"text" => "Without?"})

      export = Export.build()
      [edison] = export["formats"]
      [with, without] = Enum.flat_map(edison["topics"], & &1["questions"])
      assert with["explanation"] == "Line 1\nLine 2"
      refute Map.has_key?(without, "explanation")

      json = Export.to_json()
      MillenniumQuiz.Repo.delete_all(Quiz.Format)
      assert {:ok, _} = Import.run(json)

      explanations =
        Quiz.list_formats()
        |> Enum.flat_map(&Quiz.get_format!(&1.id).topics)
        |> Enum.flat_map(& &1.questions)
        |> Map.new(&{&1.text, &1.explanation})

      assert explanations == %{"With?" => "Line 1\nLine 2", "Without?" => nil}
    end

    test "an explanation that is not text, or too long, is refused" do
      pack = fn explanation ->
        Jason.encode!(%{
          "version" => 1,
          "formats" => [
            %{
              "name" => "X",
              "date" => "2010-03-01",
              "topics" => [
                %{
                  "name" => "T",
                  "questions" => [
                    %{
                      "text" => "Q?",
                      "explanation" => explanation,
                      "choices" => [
                        %{"text" => "a", "correct" => true},
                        %{"text" => "b", "correct" => false}
                      ]
                    }
                  ]
                },
                %{"name" => "U", "questions" => []}
              ]
            }
          ]
        })
      end

      assert {:error, _} = Import.run(pack.(5))

      assert {:ok, %{formats_created: 0, formats_failed: [{"X", msg}]}} =
               Import.run(pack.(String.duplicate("x", 2001)))

      assert msg =~ "explanation is too long"
    end
  end

  describe "admin form" do
    setup :register_and_log_in_user

    test "saves an explanation, and a question without one still saves", %{conn: conn} do
      topic = hd(format_fixture().topics)
      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")
      assert has_element?(view, "textarea#question_explanation")

      params = fn text, explanation ->
        %{
          text: text,
          explanation: explanation,
          choices: %{
            "0" => %{text: "Yes", correct: "true"},
            "1" => %{text: "No", correct: "false"},
            "2" => %{text: "Maybe", correct: "false"},
            "3" => %{text: "Never", correct: "false"}
          }
        }
      end

      view |> form("#question-form", question: params.("With?", "It is so.")) |> render_submit()

      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")
      view |> form("#question-form", question: params.("Without?", "")) |> render_submit()

      questions = MillenniumQuiz.Repo.all(from q in Question, where: q.topic_id == ^topic.id)

      assert Map.new(questions, &{&1.text, &1.explanation}) == %{
               "With?" => "It is so.",
               "Without?" => nil
             }
    end
  end

  describe "the reveal" do
    test "shows the explanation with the correct answer, above the way back to the board", %{
      conn: conn
    } do
      format = format_fixture()
      question_fixture(hd(format.topics), %{"explanation" => "Pot of Greed draws two."})
      question_fixture(List.last(format.topics))

      view = play_to_reveal(conn, format)
      assert has_element?(view, "#reveal #explanation", "Pot of Greed draws two.")
      assert has_element?(view, "#reveal #next-round")

      html = render(view)
      {explanation_at, _} = :binary.match(html, "id=\"explanation\"")
      {button_at, _} = :binary.match(html, "id=\"next-round\"")
      {correct_at, _} = :binary.match(html, "data-correct=\"true\"")
      assert correct_at < explanation_at and explanation_at < button_at
    end

    test "is not shown while the question is being answered", %{conn: conn} do
      format = format_fixture()
      question_fixture(hd(format.topics), %{"explanation" => "Secret until the reveal."})
      question_fixture(List.last(format.topics))

      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"], mode: :free)
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")
      view |> element("#question-0") |> render_click()
      view |> element("#choice-0") |> render_click()

      refute render(view) =~ "Secret until the reveal."
      refute has_element?(view, "#explanation")
    end

    test "a question without an explanation shows no explanation block", %{conn: conn} do
      format = format_fixture()
      question_fixture(hd(format.topics))
      question_fixture(List.last(format.topics))

      view = play_to_reveal(conn, format)
      assert has_element?(view, "#reveal")
      refute has_element?(view, "#explanation")
    end
  end
end
