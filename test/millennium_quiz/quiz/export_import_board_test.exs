defmodule MillenniumQuiz.Quiz.ExportImportBoardTest do
  use MillenniumQuiz.DataCase, async: false

  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{CardSourcesStub, Cards, Quiz, Release, Repo}
  alias MillenniumQuiz.Cards.Card
  alias MillenniumQuiz.Quiz.{Export, Format, Import, Question}

  @reborn 83_764_718
  @plain 11_111_111

  setup do
    CardSourcesStub.stub!()
    Repo.delete_all(Format)
    :ok
  end

  defp player(extra) do
    Map.merge(
      %{
        "lp" => 8000,
        "monsters" => List.duplicate(nil, 5),
        "spells" => List.duplicate(nil, 5)
      },
      extra
    )
  end

  defp board(p1 \\ %{}, extra \\ %{}) do
    Map.merge(%{"v" => 1, "players" => [player(p1), player(%{})]}, extra)
  end

  defp monsters(cards), do: Enum.take(cards ++ List.duplicate(nil, 5), 5)

  defp with_card(code), do: board(%{"monsters" => monsters([%{"code" => code, "pos" => "atk"}])})

  # One format of the given date with one question that has `board`.
  defp board_quiz(board, date \\ "2020-01-01") do
    format = format_fixture(%{"name" => "Edison", "date" => date})
    [topic | _] = format.topics

    {:ok, question} =
      Quiz.create_question(topic, %{
        "text" => "Which is [Monster Reborn]?",
        "choices" => choices_params(["A", "B", "C"], 1),
        "board" => board
      })

    question
  end

  defp questions, do: Repo.all(Question)

  defp export_questions,
    do:
      get_in(Export.build(), ["formats", Access.all(), "topics", Access.all(), "questions"])
      |> List.flatten()

  defp strip(export), do: Map.delete(export, "exported_at")

  defp pool_card(password, attrs) do
    Repo.insert!(
      struct!(
        Card,
        Map.merge(
          %{
            name: "Card #{password}",
            password: password,
            frame_type: "effect",
            fetched_at: DateTime.utc_now(:second)
          },
          attrs
        )
      )
    )
  end

  # Stored boards are normalised; the file carries exactly that.
  test "export carries the stored board, only on questions that have one" do
    {:ok, plain} = Cards.import(@plain)
    stored = board_quiz(with_card(plain.password)).board
    format = Repo.get_by!(Format, name: "Edison") |> Repo.preload(:topics)
    question_fixture(List.last(format.topics), %{"text" => "No board?"})

    [with, without] =
      Enum.sort_by(export_questions(), &(&1["board"] == nil))

    assert with["board"] == stored
    refute Map.has_key?(without, "board")
    assert {:ok, _} = Jason.decode(Export.to_json())
  end

  test "a round trip restores the board, reveal_all kept, and counts it" do
    {:ok, _} = Cards.import(@plain)
    board_quiz(with_card(@plain) |> Map.put("reveal_all", true))
    before = Export.build()
    json = Export.to_json()
    Repo.delete_all(Format)

    assert {:ok, summary} = Import.run(json, pause_ms: 0)
    assert summary.questions == 1
    assert summary.boards == 1
    assert summary.boards_skipped == 0
    assert summary.warnings == []
    assert [%{board: %{"reveal_all" => true}}] = questions()
    assert strip(Export.build()) == strip(before)

    assert "Boards: 1 restored, 0 skipped" in Release.import_report({:ok, summary})
  end

  test "reveal_all false is kept as well" do
    {:ok, _} = Cards.import(@plain)
    board_quiz(with_card(@plain))
    json = Export.to_json()
    Repo.delete_all(Format)

    assert {:ok, %{boards: 1}} = Import.run(json, pause_ms: 0)
    assert [%{board: %{"reveal_all" => false}}] = questions()
  end

  test "a card of the board missing from the pool is fetched" do
    {:ok, _} = Cards.import(@plain)
    {:ok, _} = Cards.import(@reborn)

    board_quiz(
      board(%{"monsters" => monsters([%{"code" => @plain}]), "hand" => [%{"code" => @reborn}]})
    )

    json = Export.to_json()
    Repo.delete_all(Format)
    Repo.delete_all(Card)

    assert {:ok, summary} = Import.run(json, pause_ms: 0)
    assert summary.boards == 1
    assert summary.boards_skipped == 0
    assert summary.warnings == []
    assert Repo.get_by(Card, password: @plain)
    assert Repo.get_by(Card, password: @reborn)
    assert [%{board: %{"players" => [%{"hand" => [%{"code" => @reborn}]}, _]}}] = questions()
  end

  test "a card that cannot be fetched drops the board, not the question" do
    board_quiz(with_card(424_242))
    json = Export.to_json()
    Repo.delete_all(Format)

    assert {:ok, summary} = Import.run(json, pause_ms: 0)
    assert summary.formats_created == 1
    assert summary.questions == 1
    assert summary.boards == 0
    assert summary.boards_skipped == 1
    assert [w] = summary.warnings
    assert w =~ "Edison / Monsters / question 1"
    assert w =~ "Which is [Monster Reborn]?"
    assert w =~ "card 424242 could not be fetched"

    assert [%{board: nil, text: "Which is [Monster Reborn]?"} = q] =
             Repo.all(Question)

    assert length(q.choices) == 3
    assert "Boards: 0 restored, 1 skipped" in Release.import_report({:ok, summary})
  end

  test "an unfetchable card does not stop the other boards" do
    {:ok, _} = Cards.import(@plain)
    question = board_quiz(with_card(424_242))
    format = Repo.get_by!(Format, name: "Edison") |> Repo.preload(:topics)

    {:ok, _} =
      Quiz.create_question(List.last(format.topics), %{
        "text" => "Fine?",
        "choices" => choices_params(),
        "board" => with_card(@plain)
      })

    assert question.id
    json = Export.to_json()
    Repo.delete_all(Format)

    assert {:ok, %{boards: 1, boards_skipped: 1, questions: 2}} = Import.run(json, pause_ms: 0)
  end

  test "a zone the format's Master Rule lacks drops the board" do
    {:ok, _} = Cards.import(@plain)
    emz = board(%{}, %{"emz" => [%{"code" => @plain, "pos" => "atk"}, nil]})
    # valid in a 2020 format ...
    board_quiz(emz, "2020-01-01")
    json = Export.to_json()
    Repo.delete_all(Format)
    assert {:ok, %{boards: 1, boards_skipped: 0}} = Import.run(json, pause_ms: 0)

    # ... not in the 2010 format of the same file
    Repo.delete_all(Format)

    file =
      json
      |> Jason.decode!()
      |> put_in(["formats", Access.at(0), "date"], "2010-03-01")

    assert {:ok, summary} = Import.run(file, pause_ms: 0)
    assert summary.boards == 0 and summary.boards_skipped == 1
    assert [w] = summary.warnings
    assert w =~ "extra monster zone 1" and w =~ "Master Rule"
    assert [%{board: nil}] = questions()
  end

  test "a card released after the format's date drops the board" do
    pool_card(555, %{tcg_release_date: ~D[2015-01-01], name: "Newcomer"})
    board_quiz(with_card(555), "2020-01-01")
    json = Export.to_json()
    Repo.delete_all(Format)

    file = json |> Jason.decode!() |> put_in(["formats", Access.at(0), "date"], "2010-03-01")

    assert {:ok, summary} = Import.run(file, pause_ms: 0)
    assert summary.questions == 1
    assert summary.boards_skipped == 1
    assert [w] = summary.warnings
    assert w =~ "Newcomer (555) was released on 2015-01-01"
    assert [%{board: nil}] = questions()
  end

  test "a malformed board costs the board, not the file" do
    board_quiz(board())
    json = Export.to_json()
    Repo.delete_all(Format)

    file =
      json
      |> Jason.decode!()
      |> put_in(
        ["formats", Access.at(0), "topics", Access.at(0), "questions", Access.at(0), "board"],
        %{"v" => 2}
      )

    assert {:ok, summary} = Import.run(file, pause_ms: 0)
    assert summary.questions == 1
    assert summary.boards == 0 and summary.boards_skipped == 1
    assert [w] = summary.warnings
    assert w =~ "board v: must be 1"
    assert [%{board: nil}] = questions()
  end

  test "a backup without boards imports with none and says so" do
    format = format_fixture(%{"name" => "Plain"})
    question_fixture(hd(format.topics))
    json = Export.to_json()
    refute json =~ "\"board\""
    Repo.delete_all(Format)

    assert {:ok, summary} = Import.run(json, pause_ms: 0)
    assert summary.boards == 0 and summary.boards_skipped == 0
    assert [%{board: nil}] = questions()
    assert "Boards: 0 restored, 0 skipped" in Release.import_report({:ok, summary})
  end

  test "an existing format is skipped and its boards are not counted" do
    {:ok, _} = Cards.import(@plain)
    board_quiz(with_card(@plain))
    assert {:ok, summary} = Import.run(Export.to_json(), pause_ms: 0)
    assert summary.formats_skipped == ["Edison"]
    assert summary.boards == 0 and summary.boards_skipped == 0
  end
end
