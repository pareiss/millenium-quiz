defmodule MillenniumQuizWeb.QuestionSourceTest do
  @moduledoc """
  The optional credit line (`source`) of a question: schema, game snapshot,
  backups, the admin form and the board dialog (the only place it is shown).
  """
  use MillenniumQuizWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import MillenniumQuiz.DataCase, only: [errors_on: 1]
  import Ecto.Query, only: [from: 2]
  import MillenniumQuiz.QuizFixtures
  import MillenniumQuiz.BoardGameFixtures, only: [board_format_fixture: 0]

  alias MillenniumQuiz.{Game, Games, Quiz, Repo}
  alias MillenniumQuiz.Quiz.{Export, Import, Question}

  @credit "Puzzle by Someone, CC BY-SA 4.0 (example.org/puzzles/7)"

  describe "the question" do
    test "a source is optional, a blank one is stored as none" do
      topic = hd(format_fixture().topics)

      assert question_fixture(topic).source == nil
      assert question_fixture(topic, %{"source" => "   "}).source == nil

      kept = question_fixture(topic, %{"source" => "  Someone  "})
      assert Quiz.get_question!(kept.id).source == "Someone"
    end

    test "a source can be removed again" do
      question = question_fixture(hd(format_fixture().topics), %{"source" => "Someone"})
      assert {:ok, q} = Quiz.update_question(question, %{"source" => ""})
      assert q.source == nil
    end

    test "a source of 300 characters is fine, a longer one is refused" do
      topic = hd(format_fixture().topics)

      attrs = fn source ->
        %{"text" => "Q?", "choices" => choices_params(), "source" => source}
      end

      assert {:ok, _} =
               Quiz.create_question(
                 topic,
                 attrs.(String.duplicate("x", Question.max_source_length()))
               )

      assert Question.max_source_length() == 300

      assert {:error, cs} =
               Quiz.create_question(
                 topic,
                 attrs.(String.duplicate("x", Question.max_source_length() + 1))
               )

      assert %{source: [_]} = errors_on(cs)
    end
  end

  describe "the game snapshot" do
    test "keeps the source; older snapshots load without it" do
      format = format_fixture()
      question_fixture(hd(format.topics), %{"source" => "Someone"})
      question_fixture(List.last(format.topics))

      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"], mode: :free)
      {:ok, %{game: game}} = Games.fetch_game(id)
      assert game.questions |> Enum.map(& &1.source) |> Enum.sort() == [nil, "Someone"]

      map = game |> Game.to_map() |> Jason.encode!() |> Jason.decode!()
      old = update_in(map, ["questions"], fn qs -> Enum.map(qs, &Map.delete(&1, "source")) end)

      assert Enum.all?(Game.from_map(old).questions, &(&1.source == nil))
      assert game.questions == Game.from_map(map).questions
    end
  end

  describe "backups" do
    setup do
      Repo.delete_all(Quiz.Format)
      :ok
    end

    test "the source survives an export and import; no key when there is none" do
      format = format_fixture(%{"name" => "Edison"})
      [monsters, spells] = format.topics
      question_fixture(monsters, %{"text" => "With?", "source" => @credit})
      question_fixture(spells, %{"text" => "Without?"})

      [edison] = Export.build()["formats"]
      [with, without] = Enum.flat_map(edison["topics"], & &1["questions"])
      assert with["source"] == @credit
      refute Map.has_key?(without, "source")

      json = Export.to_json()
      Repo.delete_all(Quiz.Format)
      assert {:ok, _} = Import.run(json)

      sources =
        Quiz.list_formats()
        |> Enum.flat_map(&Quiz.get_format!(&1.id).topics)
        |> Enum.flat_map(& &1.questions)
        |> Map.new(&{&1.text, &1.source})

      assert sources == %{"With?" => @credit, "Without?" => nil}
    end

    test "a backup from before sources (no key) still imports" do
      json =
        Jason.encode!(%{
          "version" => 1,
          "formats" => [
            %{
              "name" => "Old",
              "date" => "2010-03-01",
              "topics" => [
                %{"name" => "T", "questions" => [old_question()]},
                %{"name" => "U", "questions" => []}
              ]
            }
          ]
        })

      assert {:ok, %{formats_created: 1}} = Import.run(json)
      assert [%{source: nil}] = Repo.all(Question)
    end

    test "a source that is not text, or too long, is refused" do
      pack = fn source ->
        Jason.encode!(%{
          "version" => 1,
          "formats" => [
            %{
              "name" => "X",
              "date" => "2010-03-01",
              "topics" => [
                %{"name" => "T", "questions" => [Map.put(old_question(), "source", source)]},
                %{"name" => "U", "questions" => []}
              ]
            }
          ]
        })
      end

      assert {:error, _} = Import.run(pack.(5))

      assert {:ok, %{formats_created: 0, formats_failed: [{"X", msg}]}} =
               Import.run(pack.(String.duplicate("x", 301)))

      assert msg =~ "source is too long"
    end

    defp old_question do
      %{
        "text" => "Q?",
        "choices" => [
          %{"text" => "a", "correct" => true},
          %{"text" => "b", "correct" => false}
        ]
      }
    end
  end

  describe "admin form" do
    setup :register_and_log_in_user

    test "saves a source, and a question without one still saves", %{conn: conn} do
      topic = hd(format_fixture().topics)
      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")
      assert has_element?(view, "input#question_source[maxlength='300']")

      params = fn text, source ->
        %{
          text: text,
          source: source,
          choices: %{
            "0" => %{text: "Yes", correct: "true"},
            "1" => %{text: "No", correct: "false"},
            "2" => %{text: "Maybe", correct: "false"},
            "3" => %{text: "Never", correct: "false"}
          }
        }
      end

      view |> form("#question-form", question: params.("With?", "By Someone")) |> render_submit()

      {:ok, view, _html} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")
      view |> form("#question-form", question: params.("Without?", "")) |> render_submit()

      questions = Repo.all(from q in Question, where: q.topic_id == ^topic.id)

      assert Map.new(questions, &{&1.text, &1.source}) == %{
               "With?" => "By Someone",
               "Without?" => nil
             }
    end

    test "editing shows the stored source", %{conn: conn} do
      question = question_fixture(hd(format_fixture().topics), %{"source" => "By Someone"})
      {:ok, view, _html} = live(conn, ~p"/admin/questions/#{question.id}/edit")
      assert has_element?(view, ~s(input#question_source[value="By Someone"]))
    end
  end

  describe "the board dialog" do
    setup do
      ctx = board_format_fixture()
      {:ok, ctx}
    end

    defp open_dialog(conn, format) do
      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"], [])
      {:ok, _} = Games.choose(id, 0)
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")
      view |> element("#board-button") |> render_click()
      {id, view}
    end

    test "shows 'Source: ...' when the question has one", %{
      conn: conn,
      format: format,
      question: question
    } do
      question |> Ecto.Changeset.change(source: @credit) |> Repo.update!()

      {_id, view} = open_dialog(conn, format)
      assert has_element?(view, "#board-dialog #board-dialog-source", "Source: " <> @credit)
    end

    test "shows nothing for a question without one", %{conn: conn, format: format} do
      {_id, view} = open_dialog(conn, format)
      assert has_element?(view, "#board-dialog")
      refute has_element?(view, "#board-dialog-source")
      refute render(view) =~ "Source:"
    end

    test "a game from before sources shows nothing", %{
      conn: conn,
      format: format,
      question: question
    } do
      question |> Ecto.Changeset.change(source: @credit) |> Repo.update!()
      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"], [])
      {:ok, _} = Games.choose(id, 0)

      # the snapshot as an older version saved it: no "source" key
      record = Repo.get!(MillenniumQuiz.Games.GameRecord, id)

      old =
        update_in(record.state, ["questions"], fn qs ->
          Enum.map(qs, &Map.delete(&1, "source"))
        end)

      record |> Ecto.Changeset.change(state: old) |> Repo.update!()

      # the running server holds the game in memory: stop it so the saved one is loaded
      GenServer.stop(MillenniumQuiz.Games.Server.via(id))

      {:ok, view, _html} = live(conn, ~p"/games/#{id}")
      view |> element("#board-button") |> render_click()
      assert has_element?(view, "#board-dialog")
      refute has_element?(view, "#board-dialog-source")
      refute render(view) =~ "Source:"
    end

    test "is not shown for a question without a board, whatever the source", %{
      conn: conn,
      format: format
    } do
      other = format.topics |> List.last() |> Map.fetch!(:questions) |> hd()
      other |> Ecto.Changeset.change(source: @credit) |> Repo.update!()

      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"], [])
      {:ok, _} = Games.choose(id, 2)
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")
      refute has_element?(view, "#board-button")
      refute render(view) =~ @credit
    end

    test "a long source with an unbroken word is held by the wrapping classes", %{
      conn: conn,
      format: format,
      question: question
    } do
      long = String.duplicate("W", 120) <> " " <> String.duplicate("long ", 40)
      question |> Ecto.Changeset.change(source: String.slice(long, 0, 300)) |> Repo.update!()

      {_id, view} = open_dialog(conn, format)
      assert has_element?(view, "#board-dialog-source.min-w-0.\\[overflow-wrap\\:anywhere\\]")
    end
  end
end
