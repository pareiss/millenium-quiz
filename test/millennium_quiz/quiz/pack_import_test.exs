defmodule MillenniumQuiz.Quiz.PackImportTest do
  use MillenniumQuiz.DataCase, async: false

  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{CardSourcesStub, Cards, Quiz, Repo}
  alias MillenniumQuiz.Quiz.{PackImport, Question, Topic}

  @plain 11_111_111
  @reborn 83_764_718

  setup do
    CardSourcesStub.stub!()
    {:ok, _} = Cards.import(@plain)
    format = format_fixture(%{"name" => "Edison", "date" => "2020-01-01"})
    {:ok, format: format}
  end

  defp player(extra \\ %{}) do
    Map.merge(
      %{"lp" => 8000, "monsters" => List.duplicate(nil, 5), "spells" => List.duplicate(nil, 5)},
      extra
    )
  end

  defp board(code \\ @plain) do
    %{
      "v" => 1,
      "players" => [
        player(%{"monsters" => [%{"code" => code, "pos" => "atk"}, nil, nil, nil, nil]}),
        player()
      ]
    }
  end

  defp q(text, extra \\ %{}) do
    Map.merge(
      %{
        "text" => text,
        "choices" => [
          %{"text" => "Summon it", "correct" => true},
          %{"text" => "End the turn", "correct" => false}
        ]
      },
      extra
    )
  end

  defp pack(topics, extra \\ %{}),
    do: Map.merge(%{"version" => 1, "topics" => topics}, extra)

  defp topic(name, questions), do: %{"name" => name, "questions" => questions}

  defp run(format, pack), do: PackImport.run(format, pack, pause_ms: 0)

  defp topic_questions(format, name) do
    Repo.all(
      from t in Topic,
        where: t.format_id == ^format.id and t.name == ^name,
        join: x in Question,
        on: x.topic_id == t.id,
        order_by: x.position,
        select: x
    )
  end

  test "creates a topic with its questions, boards and order", %{format: format} do
    pack = pack([topic("Next play: B08", [q("Step 1?", %{"board" => board()}), q("Step 2?")])])

    assert {:ok, r} = run(format, pack)
    assert r.imported == 2 and r.boards == 1 and r.failed == [] and r.skipped == 0
    assert r.topics_created == ["Next play: B08"]

    assert [%{text: "Step 1?", position: 0, board: %{"v" => 1}}, %{text: "Step 2?", position: 1}] =
             topic_questions(format, "Next play: B08")

    assert Repo.get!(Quiz.Format, format.id).date == format.date
    assert Enum.at(Quiz.get_format!(format.id).topics, 2).position == 2
  end

  test "an existing topic gets the questions at the hard end, matched by name", %{format: format} do
    existing = hd(format.topics)
    question_fixture(existing, %{"text" => "Already here"})

    assert {:ok, r} = run(format, pack([topic("  monsters ", [q("New one?")])]))
    assert r.imported == 1 and r.topics_created == []
    assert ["Already here", "New one?"] = Enum.map(topic_questions(format, "Monsters"), & &1.text)
    assert length(Quiz.get_format!(format.id).topics) == 2
  end

  test "importing the same pack twice adds nothing", %{format: format} do
    pack = pack([topic("Puzzle", [q("Step 1?", %{"board" => board()})])])
    assert {:ok, %{imported: 1}} = run(format, pack)
    assert {:ok, %{imported: 0, skipped: 1, failed: [], topics_created: []}} = run(format, pack)
    assert length(topic_questions(format, "Puzzle")) == 1
  end

  test "same text with another board is a different question", %{format: format} do
    other = put_in(board(), ["players", Access.at(1), "lp"], 4000)

    pack =
      pack([topic("Puzzle", [q("Next?", %{"board" => board()}), q("Next?", %{"board" => other})])])

    assert {:ok, %{imported: 2, skipped: 0}} = run(format, pack)
  end

  test "reports each bad question and imports the others", %{format: format} do
    bad_choices =
      q("No answer?", %{
        "choices" => [%{"text" => "a", "correct" => false}, %{"text" => "b", "correct" => false}]
      })

    bad_board = q("Bad board?", %{"board" => %{"v" => 2}})
    missing = q("Unknown card?", %{"board" => board(424_242)})

    pack =
      pack([
        topic("Puzzle", [
          q("Good 1?", %{"board" => board()}),
          bad_choices,
          bad_board,
          missing,
          q("Good 2?")
        ])
      ])

    assert {:ok, r} = run(format, pack)
    assert r.imported == 2
    assert [f1, f2, f3] = r.failed
    assert %{topic: "Puzzle", number: 2, text: "No answer?"} = f1
    assert f1.reason =~ "exactly one answer"
    assert f2.number == 3 and f2.reason =~ "board" and f2.reason =~ "must be 1"
    assert f3.number == 4 and f3.reason =~ "card 424242 could not be fetched"
    assert ["Good 1?", "Good 2?"] = Enum.map(topic_questions(format, "Puzzle"), & &1.text)

    lines = PackImport.report_lines(r)
    assert Enum.any?(lines, &(&1 =~ "Failed: Puzzle, question 3"))
  end

  test "failures of a topic are listed in question order", %{format: format} do
    bad_choices =
      q("No answer?", %{
        "choices" => [%{"text" => "a", "correct" => false}, %{"text" => "b", "correct" => false}]
      })

    # Question 1 only fails once its card could not be fetched, question 2 fails
    # when it is judged; the report still lists 1 before 2.
    missing = q("Unknown card?", %{"board" => board(424_242)})

    assert {:ok, r} = run(format, pack([topic("Puzzle", [missing, bad_choices, q("Good?")])]))
    assert [1, 2] = Enum.map(r.failed, & &1.number)
  end

  test "a card released after the format's date fails that question only", %{format: format} do
    pool =
      Repo.insert!(%MillenniumQuiz.Cards.Card{
        name: "Newcomer",
        password: 555,
        frame_type: "effect",
        tcg_release_date: ~D[2021-01-01],
        fetched_at: DateTime.utc_now(:second)
      })

    assert pool.id

    pack =
      pack([
        topic("Puzzle", [
          q("Too new?", %{"board" => board(555)}),
          q("Fine?", %{"board" => board()})
        ])
      ])

    assert {:ok, %{imported: 1, failed: [f]}} = run(format, pack)
    assert f.reason =~ "Newcomer (555) was released on 2021-01-01"
  end

  test "a board card the pool lacks is fetched", %{format: format} do
    assert {:ok, %{imported: 1, failed: []}} =
             run(format, pack([topic("Puzzle", [q("Fetch?", %{"board" => board(@reborn)})])]))

    assert Repo.get_by(MillenniumQuiz.Cards.Card, password: @reborn)
  end

  test "question cards are linked, an unfetchable one is unlinked with a warning", %{
    format: format
  } do
    cards = [
      %{"password" => @plain, "name" => "Plain Monster"},
      %{"password" => 424_242, "name" => "Ghost"}
    ]

    pack =
      pack([topic("Puzzle", [q("Is [Plain Monster] or [Ghost] here?", %{"cards" => cards})])])

    assert {:ok, %{imported: 1, warnings: [_renamed, w]}} = run(format, pack)
    assert w =~ "Ghost (424242) could not be fetched"
    assert [%{text: text}] = topic_questions(format, "Puzzle")
    assert text =~ "Ghost" and not (text =~ "[Ghost]")

    # The stored text differs from the pack's: importing again must still find it.
    assert {:ok, %{imported: 0, skipped: 1}} = run(format, pack)
    assert [_] = topic_questions(format, "Puzzle")
  end

  test "a format with six topics cannot take a new one, existing ones still work", %{
    format: format
  } do
    for n <- 3..6, do: Repo.insert!(%Topic{format_id: format.id, name: "T#{n}", position: n})

    pack = pack([topic("Brand new", [q("Where?")]), topic("T3", [q("Here?")])])
    assert {:ok, r} = run(format, pack)
    assert r.imported == 1 and r.topics_created == []
    assert [%{topic: "Brand new", reason: reason}] = r.failed
    assert reason =~ "already has 6 topics"
  end

  test "a topic whose questions all fail is not created", %{format: format} do
    assert {:ok, r} = run(format, pack([topic("Empty", [%{"text" => "x"}])]))
    assert r.imported == 0 and r.topics_created == [] and length(r.failed) == 1
    assert length(Quiz.get_format!(format.id).topics) == 2
  end

  test "the pack as a whole is rejected for structural problems", %{format: format} do
    assert {:error, "The file is not valid JSON."} = PackImport.run(format, "nope")
    assert {:error, "This is not a question pack" <> _} = run(format, %{"topics" => []})
    assert {:error, "Unsupported pack version 2" <> _} = run(format, %{"version" => 2})
    assert {:error, "The pack has no list of topics."} = run(format, %{"version" => 1})
    assert {:error, "The pack has no topics."} = run(format, pack([]))
    assert {:error, "Topic 1:" <> _} = run(format, pack([%{"questions" => []}]))
    assert {:error, "credits" <> _} = run(format, pack([topic("A", [])], %{"credits" => 5}))
    assert {:error, "The file must contain a JSON object."} = PackImport.run(format, [1], [])
    assert Quiz.questions_for_format(format.id) == []
  end

  test "accepts the JSON text and keeps the credits for the report", %{format: format} do
    json =
      Jason.encode!(pack([topic("Puzzle", [q("Hi?")])], %{"credits" => "By Someone, CC BY-SA"}))

    assert {:ok, %{imported: 1, credits: "By Someone, CC BY-SA"}} =
             PackImport.run(format.id, json, pause_ms: 0)
  end

  test "two entries of the same topic name are one topic", %{format: format} do
    pack = pack([topic("Puzzle", [q("One?")]), topic("puzzle", [q("Two?")])])
    assert {:ok, %{imported: 2, topics_created: ["Puzzle"]}} = run(format, pack)
    assert ["One?", "Two?"] = Enum.map(topic_questions(format, "Puzzle"), & &1.text)
  end

  test "a card unfetchable on the first import and fetched on the retry is not imported twice", %{
    format: format
  } do
    cards = [%{"password" => 424_242, "name" => "Ghost"}]
    pack = pack([topic("Puzzle", [q("Is [Ghost] here?", %{"cards" => cards})])])

    # first run: the source does not know the card, so it is unlinked
    assert {:ok, %{imported: 1}} = run(format, pack)
    assert [%{text: "Is Ghost here?"}] = topic_questions(format, "Puzzle")

    # the retry: the card can be fetched now, the text would be "[Ghost]"
    CardSourcesStub.stub_with_card!(%{password: 424_242, name: "Ghost", date: "2002-03-08"})
    assert {:ok, %{imported: 0, skipped: 1}} = run(format, pack)
    assert [_] = topic_questions(format, "Puzzle")
  end

  test "a card renamed between two imports does not make the question new", %{format: format} do
    cards = [%{"password" => @plain, "name" => "Plain Card"}]
    pack = pack([topic("Puzzle", [q("Is [Plain Card] here?", %{"cards" => cards})])])

    assert {:ok, %{imported: 1}} = run(format, pack)
    assert [%{text: "Is [Plain Card] here?"}] = topic_questions(format, "Puzzle")

    Repo.get_by!(MillenniumQuiz.Cards.Card, password: @plain)
    |> Ecto.Changeset.change(name: "Renamed Monster")
    |> Repo.update!()

    assert {:ok, %{imported: 0, skipped: 1}} = run(format, pack)
    assert [_] = topic_questions(format, "Puzzle")
  end

  test "different choices are still a different question even with card links", %{format: format} do
    cards = [%{"password" => @plain, "name" => "Plain Monster"}]
    other = [%{"text" => "A", "correct" => false}, %{"text" => "B", "correct" => true}]

    assert {:ok, %{imported: 1}} =
             run(format, pack([topic("P", [q("[Plain Monster]?", %{"cards" => cards})])]))

    assert {:ok, %{imported: 1, skipped: 0}} =
             run(
               format,
               pack([topic("P", [q("Plain Monster?", %{"cards" => cards, "choices" => other})])])
             )
  end

  test "same text and choices but different cards are different questions", %{format: format} do
    a = [%{"password" => @plain, "name" => "Plain Card"}]
    b = [%{"password" => @reborn, "name" => "Monster Reborn"}]
    qa = q("Can [Plain Card] be Special Summoned?", %{"cards" => a})
    qb = q("Can [Monster Reborn] be Special Summoned?", %{"cards" => b})

    # within one pack
    assert {:ok, %{imported: 2, skipped: 0}} = run(format, pack([topic("One", [qa, qb])]))

    # against stored questions
    assert {:ok, %{imported: 1, skipped: 0}} = run(format, pack([topic("Two", [qa])]))
    assert {:ok, %{imported: 1, skipped: 0}} = run(format, pack([topic("Two", [qb])]))
    assert {:ok, %{imported: 0, skipped: 2}} = run(format, pack([topic("Two", [qa, qb])]))
  end

  test "same text and choices that do not name the cards, but other cards, are different", %{
    format: format
  } do
    a = [%{"password" => @plain}]
    b = [%{"password" => @reborn}]
    qa = q("Which Attribute does this card have?", %{"cards" => a})
    qb = q("Which Attribute does this card have?", %{"cards" => b})

    # within one pack
    assert {:ok, %{imported: 2, skipped: 0}} = run(format, pack([topic("One", [qa, qb])]))

    # against stored questions
    assert {:ok, %{imported: 1, skipped: 0}} = run(format, pack([topic("Two", [qa])]))
    assert {:ok, %{imported: 1, skipped: 0}} = run(format, pack([topic("Two", [qb])]))
    assert {:ok, %{imported: 0, skipped: 2}} = run(format, pack([topic("Two", [qa, qb])]))
  end

  test "the same cards with another owner are a different question", %{format: format} do
    one = q("Whose card is this?", %{"cards" => [%{"password" => @plain, "owner" => 1}]})
    two = q("Whose card is this?", %{"cards" => [%{"password" => @plain, "owner" => 2}]})

    assert {:ok, %{imported: 2, skipped: 0}} = run(format, pack([topic("One", [one, two])]))
    assert {:ok, %{imported: 0, skipped: 2}} = run(format, pack([topic("One", [one, two])]))

    assert {:ok, %{imported: 1}} = run(format, pack([topic("Two", [one])]))
    assert {:ok, %{imported: 1, skipped: 0}} = run(format, pack([topic("Two", [two])]))
  end

  test "the order of the cards matters", %{format: format} do
    a = %{"password" => @plain}
    b = %{"password" => @reborn}
    one = q("Which comes first?", %{"cards" => [a, b]})
    two = q("Which comes first?", %{"cards" => [b, a]})

    assert {:ok, %{imported: 2, skipped: 0}} = run(format, pack([topic("One", [one, two])]))
  end

  test "text that differs only in case is a different question", %{format: format} do
    pack = pack([topic("P", [q("Is it the ATK?"), q("Is it the atk?")])])
    assert {:ok, %{imported: 2, skipped: 0}} = run(format, pack)
  end

  test "a card name is still matched regardless of case", %{format: format} do
    cards = [%{"password" => @plain, "name" => "Plain Card"}]

    assert {:ok, %{imported: 1}} =
             run(format, pack([topic("P", [q("Is [Plain Card] here?", %{"cards" => cards})])]))

    assert {:ok, %{imported: 0, skipped: 1}} =
             run(format, pack([topic("P", [q("Is [PLAIN CARD] here?", %{"cards" => cards})])]))
  end

  test "a card name inside another word is not blanked", %{format: format} do
    cards = [%{"password" => @plain, "name" => "Plain Card"}]
    one = q("Is [Plain Card] in the plain card game?", %{"cards" => cards})
    two = q("Is [Plain Card] in the xplain cardy game?", %{"cards" => cards})

    assert {:ok, %{imported: 2, skipped: 0}} = run(format, pack([topic("P", [one, two])]))
  end

  test "the limit of 200 questions per topic counts entries of the same name together", %{
    format: format
  } do
    many = fn prefix -> for n <- 1..120, do: q("#{prefix} #{n}?") end

    assert {:error, "Too many questions in a topic (at most 200)."} =
             run(format, pack([topic("Puzzle", many.("a")), topic("puzzle", many.("b"))]))

    assert {:ok, %{imported: 240}} =
             run(format, pack([topic("One", many.("a")), topic("Two", many.("b"))]))
  end

  describe "two imports into the same format" do
    # a second database session holds the lock, like a running import would
    defp hold_lock(format_id) do
      {:ok, conn} =
        Postgrex.start_link(
          Keyword.merge(Repo.config(), pool: DBConnection.ConnectionPool, pool_size: 1)
        )

      assert %{rows: [[true]]} =
               Postgrex.query!(conn, "SELECT pg_try_advisory_lock(7301, $1)", [format_id])

      conn
    end

    test "the second one fails with a clear message when the lock stays taken", %{format: format} do
      conn = hold_lock(format.id)

      assert {:error, "Another import into this format is running" <> _} =
               PackImport.run(format, pack([topic("Puzzle", [q("Hi?")])]),
                 pause_ms: 0,
                 lock_timeout_ms: 200
               )

      assert topic_questions(format, "Puzzle") == []
      GenServer.stop(conn)
    end

    test "the second one waits and then imports once the first is done", %{format: format} do
      conn = hold_lock(format.id)
      pack = pack([topic("Puzzle", [q("Hi?")])])

      task = Task.async(fn -> PackImport.run(format, pack, pause_ms: 0) end)
      Process.sleep(300)
      assert Task.yield(task, 0) == nil

      Postgrex.query!(conn, "SELECT pg_advisory_unlock(7301, $1)", [format.id])
      assert {:ok, %{imported: 1}} = Task.await(task)
      GenServer.stop(conn)
    end

    test "two simultaneous imports of the same pack create the topic and question once", %{
      format: format
    } do
      pack = pack([topic("Brand new", [q("Once?")])])

      results =
        1..2
        |> Enum.map(fn _ -> Task.async(fn -> PackImport.run(format, pack, pause_ms: 0) end) end)
        |> Task.await_many()

      assert [{:ok, %{imported: 1}}, {:ok, %{imported: 0, skipped: 1}}] =
               Enum.sort_by(results, fn {:ok, r} -> -r.imported end)

      assert [_] = topic_questions(format, "Brand new")
      assert Quiz.get_format!(format.id).topics |> Enum.count(&(&1.name == "Brand new")) == 1
    end

    test "different formats do not block each other", %{format: format} do
      other = format_fixture(%{"name" => "GOAT", "date" => "2005-01-01"})
      conn = hold_lock(other.id)

      assert {:ok, %{imported: 1}} =
               PackImport.run(format, pack([topic("Puzzle", [q("Hi?")])]),
                 pause_ms: 0,
                 lock_timeout_ms: 0
               )

      GenServer.stop(conn)
    end
  end
end
