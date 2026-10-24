defmodule MillenniumQuiz.Quiz.ExportImportTest do
  use MillenniumQuiz.DataCase, async: false

  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{CardSourcesStub, Cards, Quiz, Repo}
  alias MillenniumQuiz.Cards.Card
  alias MillenniumQuiz.Quiz.{Export, Format, Import}

  setup do
    CardSourcesStub.stub!()
    # the test database holds the seeded format
    clear_quiz()
    :ok
  end

  # Two formats, one question about a card, one with a points override.
  defp build_quiz do
    {:ok, reborn} = Cards.import(CardSourcesStub.reborn().password)

    format =
      format_fixture(%{
        "name" => "Edison",
        "description" => "Old times",
        "date" => "2010-03-01"
      })

    [t1, t2] = format.topics

    {:ok, _} =
      Quiz.create_question(
        t1,
        %{
          "text" => "What does [Monster Reborn] do?",
          "points" => 55,
          "choices" => choices_params(["Revives", "Burns", "Draws"], 1)
        },
        [reborn.id]
      )

    question_fixture(t1, %{"text" => "Second?"})
    question_fixture(t2, %{"text" => "Third?"})

    format_fixture(%{"name" => "Another", "date" => "2004-01-01"})
    reborn
  end

  defp strip(export), do: Map.delete(export, "exported_at")

  defp clear_quiz, do: Repo.delete_all(Format)

  test "export has the documented shape and a stable order" do
    build_quiz()
    export = Export.build()

    assert %{"version" => 1, "exported_at" => at, "formats" => [another, edison]} = export
    assert {:ok, _, _} = DateTime.from_iso8601(at)
    assert another["name"] == "Another"
    assert edison["date"] == "2010-03-01"

    [monsters, _spells] = edison["topics"]
    [first, second] = monsters["questions"]
    assert first["points"] == 55
    assert first["cards"] == [%{"password" => 83_764_718, "name" => "Monster Reborn"}]
    assert Enum.map(first["choices"], & &1["correct"]) == [false, true, false]
    assert second["text"] == "Second?"
    assert second["cards"] == []

    assert strip(Export.build()) == strip(export)
    assert {:ok, _} = Jason.decode(Export.to_json())
  end

  test "a round trip into an empty database gives an equal export" do
    build_quiz()
    before = Export.build()
    json = Export.to_json()
    clear_quiz()
    assert Export.build()["formats"] == []

    assert {:ok, summary} = Import.run(json)
    assert summary.formats_created == 2
    assert summary.topics == 4
    assert summary.questions == 3
    assert summary.cards_linked == 1
    assert summary.cards_missing == 0
    assert summary.warnings == []

    assert strip(Export.build()) == strip(before)
  end

  test "importing the same file again skips everything" do
    build_quiz()
    json = Export.to_json()
    before = Export.build()

    assert {:ok, summary} = Import.run(json)
    assert summary.formats_created == 0
    assert Enum.sort(summary.formats_skipped) == ["Another", "Edison"]
    assert summary.questions == 0
    assert strip(Export.build()) == strip(before)
  end

  test "a card that cannot be fetched is reported, the question is still created" do
    reborn = build_quiz()
    json = Export.to_json()
    clear_quiz()
    Repo.delete!(reborn)
    Req.Test.stub(MillenniumQuiz.Cards, &Plug.Conn.send_resp(&1, 404, "gone"))

    assert {:ok, summary} = Import.run(json, pause_ms: 0)
    assert summary.formats_created == 2
    assert summary.cards_missing == 1
    assert summary.cards_linked == 0
    assert [warning] = summary.warnings
    assert warning =~ "Monster Reborn"
    refute Repo.get_by(Card, password: 83_764_718)

    format = Repo.get_by!(Format, name: "Edison") |> Repo.preload(topics: :questions)
    question = format.topics |> hd() |> Map.fetch!(:questions) |> Enum.min_by(& &1.position)
    # no marker is left that points at nothing
    assert question.text == "What does Monster Reborn do?"
    assert question.points == 55
  end

  test "a card missing from the pool is fetched" do
    reborn = build_quiz()
    json = Export.to_json()
    clear_quiz()
    Repo.delete!(reborn)

    assert {:ok, %{cards_linked: 1, warnings: []}} = Import.run(json, pause_ms: 0)
    assert Repo.get_by(Card, password: 83_764_718)
  end

  test "a format that cannot be created fetches no cards" do
    reborn = build_quiz()
    good = Export.build()
    clear_quiz()
    Repo.delete!(reborn)

    test_pid = self()

    Req.Test.stub(MillenniumQuiz.Cards, fn conn ->
      send(test_pid, :fetched)
      Plug.Conn.send_resp(conn, 404, "gone")
    end)

    # "Edison" (with the card) gets too many topics for the app, though the file passes
    topic = hd(hd(good["formats"])["topics"])
    edison = Enum.find_index(good["formats"], &(&1["name"] == "Edison"))
    too_many = List.duplicate(topic, 7)
    doomed = put_in(good, ["formats", Access.at(edison), "topics"], too_many)

    assert {:ok, summary} = Import.run(doomed, pause_ms: 0)
    assert [{"Edison", msg}] = summary.formats_failed
    assert msg =~ "between 2 and 6 topics"
    assert summary.formats_created == 1
    refute_received :fetched
    refute Repo.get_by(Card, password: 83_764_718)
  end

  test "a card that is called differently now keeps its link in the text" do
    reborn = build_quiz()
    json = Export.to_json()
    clear_quiz()
    # the card is gone from the pool and comes back under its current name
    Repo.delete!(reborn)

    renamed =
      json
      |> Jason.decode!()
      |> update_in(
        ["formats", Access.all(), "topics", Access.all(), "questions", Access.all()],
        fn q ->
          update_in(q, ["cards", Access.all(), "name"], fn
            "Monster Reborn" -> "Monster Revival"
            other -> other
          end)
          |> update_in(["text"], &String.replace(&1, "[Monster Reborn]", "[Monster Revival]"))
        end
      )

    assert {:ok, summary} = Import.run(renamed, pause_ms: 0)
    assert summary.cards_linked == 1
    assert summary.cards_missing == 0
    assert [warning] = summary.warnings
    assert warning =~ "Monster Revival"
    assert warning =~ "Monster Reborn"

    format = Repo.get_by!(Format, name: "Edison") |> Repo.preload(topics: :questions)
    question = format.topics |> hd() |> Map.fetch!(:questions) |> Enum.min_by(& &1.position)
    # the marker names the card as it is called now, so it still links
    assert question.text == "What does [Monster Reborn] do?"
  end

  describe "rejected files create nothing" do
    setup do
      build_quiz()
      good = Export.build()
      clear_quiz()
      {:ok, good: good}
    end

    defp assert_rejected(input, pattern) do
      assert {:error, message} = Import.run(input)
      assert message =~ pattern
      assert Repo.aggregate(Format, :count) == 0
    end

    test "bad version, malformed JSON, wrong shapes", %{good: good} do
      assert_rejected(Map.put(good, "version", 2), "version")
      assert_rejected(Map.delete(good, "version"), "not a Millennium Quiz backup")
      assert_rejected("{not json", "not valid JSON")
      assert_rejected("[1, 2]", "JSON object")
      assert_rejected(Map.put(good, "formats", "x"), "list of formats")
      assert_rejected(put_in(good, ["formats", Access.at(1), "date"], "tomorrow"), "date")
      assert_rejected(put_in(good, ["formats", Access.at(1), "name"], 5), "name")

      assert_rejected(
        put_in(good, ["formats", Access.at(1), "topics", Access.at(0), "questions"], "x"),
        "questions"
      )

      bad_choice = %{"text" => "x", "correct" => "yes"}

      assert_rejected(
        put_in(
          good,
          ["formats", Access.at(1), "topics", Access.at(0), "questions", Access.at(0), "choices"],
          [bad_choice]
        ),
        "correct"
      )

      bad_card = %{"password" => "83764718"}

      assert_rejected(
        put_in(
          good,
          ["formats", Access.at(1), "topics", Access.at(0), "questions", Access.at(0), "cards"],
          [bad_card]
        ),
        "password"
      )
    end

    test "oversize and too many items", %{good: good} do
      assert_rejected(String.duplicate(" ", Import.max_bytes() + 1), "too large")

      many = List.duplicate(hd(good["formats"]), 51)
      assert_rejected(Map.put(good, "formats", many), "Too many formats")

      topics = List.duplicate(hd(hd(good["formats"])["topics"]), 21)

      assert_rejected(
        put_in(good, ["formats", Access.at(0), "topics"], topics),
        "too many topics"
      )

      q = hd(hd(hd(good["formats"])["topics"])["questions"] ++ [%{}])
      questions = List.duplicate(q, 201)

      assert_rejected(
        put_in(good, ["formats", Access.at(0), "topics", Access.at(0), "questions"], questions),
        "too many questions"
      )

      choices = List.duplicate(%{"text" => "a", "correct" => false}, 21)

      assert_rejected(
        put_in(
          good,
          ["formats", Access.at(1), "topics", Access.at(0), "questions", Access.at(0), "choices"],
          choices
        ),
        "too many choices"
      )
    end

    test "a format that breaks a domain rule fails alone and is not half-created", %{good: good} do
      one_topic =
        put_in(good, ["formats", Access.at(0), "topics"], [hd(hd(good["formats"])["topics"])])

      no_correct =
        put_in(
          one_topic,
          ["formats", Access.at(1), "topics", Access.at(0), "questions", Access.at(0), "choices"],
          [%{"text" => "a", "correct" => false}, %{"text" => "b", "correct" => false}]
        )

      assert {:ok, summary} = Import.run(no_correct)
      # "Another" has one topic only, "Edison" has a question without a correct answer
      assert summary.formats_created == 0
      assert [{"Another", msg1}, {"Edison", msg2}] = summary.formats_failed
      assert msg1 =~ "topics"
      assert msg2 =~ "correct"
      assert Repo.aggregate(Format, :count) == 0
      assert Repo.aggregate(Quiz.Topic, :count) == 0

      # a good format next to a broken one still comes through
      valid_second = put_in(good, ["formats", Access.at(0), "topics"], [])

      assert {:ok, %{formats_created: 1, formats_failed: [{"Another", _}]}} =
               Import.run(valid_second)
    end
  end
end
