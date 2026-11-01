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

  # Two formats, one question about a card, one with cards.
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
    refute Map.has_key?(first, "points")
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

  test "an old backup with points (integer or null) still imports, the value is ignored" do
    build_quiz()
    json = Export.to_json()
    clear_quiz()

    old =
      json
      |> Jason.decode!()
      |> update_in(["formats", Access.all(), "topics", Access.all(), "questions"], fn qs ->
        qs
        |> Enum.with_index()
        |> Enum.map(fn {q, i} -> Map.put(q, "points", if(i == 0, do: 55)) end)
      end)

    assert {:ok, summary} = Import.run(Jason.encode!(old))
    assert summary.questions == 3
    q = Repo.get_by!(MillenniumQuiz.Quiz.Question, text: "Second?")
    refute Map.has_key?(Map.from_struct(q), :points)

    assert Enum.all?(Export.build()["formats"], fn f ->
             Enum.all?(f["topics"], fn t ->
               Enum.all?(t["questions"], &(not Map.has_key?(&1, "points")))
             end)
           end)

    bad =
      put_in(
        old,
        ["formats", Access.at(1), "topics", Access.at(0), "questions", Access.at(0), "points"],
        "x"
      )

    clear_quiz()
    assert {:error, _} = Import.run(Jason.encode!(bad))
  end

  describe "avatar cards" do
    defp avatar_quiz do
      {:ok, reborn} = Cards.import(CardSourcesStub.reborn().password)
      {:ok, plain} = Cards.import(CardSourcesStub.plain().password)
      format = format_fixture(%{"name" => "Avatars", "date" => "2020-01-01"})
      {:ok, _} = Quiz.add_avatar_card(format.id, plain.id)
      {:ok, _} = Quiz.add_avatar_card(format.id, reborn.id)
      format
    end

    test "are exported in order and survive a round trip" do
      avatar_quiz()
      export = Export.build()

      assert [%{"avatar_cards" => cards}] = export["formats"]
      assert Enum.map(cards, & &1["password"]) == [11_111_111, 83_764_718]
      assert Enum.map(cards, & &1["name"]) == ["Plain Card", "Monster Reborn"]

      json = Export.to_json()
      clear_quiz()
      assert {:ok, %{formats_created: 1, warnings: []}} = Import.run(json)
      assert strip(Export.build()) == strip(export)
    end

    test "crops are exported only where stored and survive a round trip" do
      avatar_quiz()
      plain = Repo.get_by!(Card, password: 11_111_111)
      {:ok, _} = Quiz.set_avatar_crop(plain.id, %{x: 20, y: 70, zoom: 200})
      export = Export.build()

      assert [%{"avatar_cards" => [with_crop, without]}] = export["formats"]
      assert with_crop["crop"] == %{"x" => 20, "y" => 70, "zoom" => 200}
      refute Map.has_key?(without, "crop")

      json = Export.to_json()
      clear_quiz()
      Quiz.reset_avatar_crop(plain.id)
      assert {:ok, %{formats_created: 1, warnings: []}} = Import.run(json)
      assert Quiz.avatar_crop(plain.id) == %{x: 20, y: 70, zoom: 200}
      assert strip(Export.build()) == strip(export)
    end

    test "an imported crop does not overwrite a local one" do
      avatar_quiz()
      plain = Repo.get_by!(Card, password: 11_111_111)
      {:ok, _} = Quiz.set_avatar_crop(plain.id, %{x: 20, y: 70, zoom: 200})
      json = Export.to_json()
      clear_quiz()
      {:ok, _} = Quiz.set_avatar_crop(plain.id, %{x: 90, y: 10, zoom: 250})

      assert {:ok, %{formats_created: 1, warnings: []}} = Import.run(json)
      assert Quiz.avatar_crop(plain.id) == %{x: 90, y: 10, zoom: 250}
    end

    test "an invalid crop is a warning, the card is still a picture" do
      avatar_quiz()
      export = Export.build()
      plain = Repo.get_by!(Card, password: 11_111_111)

      for bad <- [
            %{"x" => 101, "y" => 50, "zoom" => 150},
            %{"x" => 50, "y" => 50, "zoom" => 99},
            %{"x" => "50", "y" => 50, "zoom" => 150},
            %{"x" => 50, "y" => 50},
            "centre"
          ] do
        bad_export =
          put_in(export, ["formats", Access.at(0), "avatar_cards", Access.at(0), "crop"], bad)

        clear_quiz()

        assert {:ok, %{formats_created: 1, warnings: [w]}} = Import.run(bad_export)
        assert w =~ "Plain Card" and w =~ "crop"
        assert Quiz.avatar_crop(plain.id) == MillenniumQuiz.Avatars.default_crop()
        assert [%{"avatar_cards" => [_, _]}] = Export.build()["formats"]
      end
    end

    test "a backup without the key imports with none" do
      avatar_quiz()

      old =
        Export.build()
        |> update_in(["formats"], fn fs -> Enum.map(fs, &Map.delete(&1, "avatar_cards")) end)

      clear_quiz()
      assert {:ok, %{formats_created: 1, warnings: []}} = Import.run(old)
      assert [%{"avatar_cards" => []}] = Export.build()["formats"]
    end

    test "a card that can't be a picture is a warning, the format is still created" do
      avatar_quiz()
      export = Export.build()
      # both cards are newer than this format's date
      late = put_in(export, ["formats", Access.at(0), "date"], "1999-01-01")
      clear_quiz()

      assert {:ok, %{formats_created: 1, warnings: [w1, w2]}} = Import.run(late)
      assert w1 =~ "Plain Card" and w2 =~ "Monster Reborn"
      assert w1 =~ "not a profile picture"
      assert [%{"avatar_cards" => []}] = Export.build()["formats"]
    end

    test "a malformed list rejects the file" do
      avatar_quiz()
      export = Export.build()
      clear_quiz()

      bad = put_in(export, ["formats", Access.at(0), "avatar_cards"], "nope")
      assert {:error, msg} = Import.run(bad)
      assert msg =~ "avatar_cards"

      bad = put_in(export, ["formats", Access.at(0), "avatar_cards"], [%{"password" => "x"}])
      assert {:error, _} = Import.run(bad)

      many = for i <- 1..41, do: %{"password" => i}
      bad = put_in(export, ["formats", Access.at(0), "avatar_cards"], many)
      assert {:error, _} = Import.run(bad)
      assert Export.build()["formats"] == []
    end
  end

  describe "card owners" do
    defp owned_quiz(owner) do
      {:ok, reborn} = Cards.import(CardSourcesStub.reborn().password)
      {:ok, plain} = Cards.import(CardSourcesStub.plain().password)
      [topic, _] = format_fixture(%{"name" => "Owners", "date" => "2020-01-01"}).topics

      {:ok, q} =
        Quiz.create_question(
          topic,
          %{"text" => "[Monster Reborn] vs [Plain Card]", "choices" => choices_params()},
          [{reborn.id, owner}, {plain.id, nil}]
        )

      {q, reborn, plain}
    end

    defp exported_cards do
      export = Export.build()
      [format] = Enum.filter(export["formats"], &(&1["name"] == "Owners"))

      format["topics"]
      |> hd()
      |> Map.fetch!("questions")
      |> Enum.find(&(&1["cards"] != []))
      |> Map.fetch!("cards")
    end

    test "are exported only when a player owns the card, and survive a round trip" do
      owned_quiz(1)

      assert exported_cards() == [
               %{"password" => 83_764_718, "name" => "Monster Reborn", "owner" => 1},
               %{"password" => 11_111_111, "name" => "Plain Card"}
             ]

      before = Export.build()
      json = Export.to_json()
      clear_quiz()
      assert {:ok, %{cards_linked: 2, warnings: []}} = Import.run(json)
      assert strip(Export.build()) == strip(before)
      assert [%{"owner" => 1}, second] = exported_cards()
      refute Map.has_key?(second, "owner")
    end

    test "a backup from before owners imports with no card owned" do
      owned_quiz(2)

      old =
        Export.build()
        |> update_in(["formats"], fn fs ->
          for f <- fs,
              do:
                update_in(f, ["topics"], fn ts ->
                  for t <- ts,
                      do:
                        update_in(t, ["questions"], fn qs ->
                          for q <- qs,
                              do:
                                update_in(q, ["cards"], fn cs ->
                                  Enum.map(cs, &Map.delete(&1, "owner"))
                                end)
                        end)
                end)
        end)

      clear_quiz()
      assert {:ok, %{questions: 1, cards_linked: 2}} = Import.run(old)
      assert Enum.all?(exported_cards(), &(not Map.has_key?(&1, "owner")))
    end

    test "an owner other than 1, 2 or null rejects the file and creates nothing" do
      owned_quiz(1)
      good = Export.build()
      clear_quiz()

      for bad <- [0, 3, "1", true, 1.5] do
        file =
          update_in(good, ["formats"], fn fs ->
            for f <- fs,
                do:
                  update_in(f, ["topics"], fn ts ->
                    for t <- ts,
                        do:
                          update_in(t, ["questions"], fn qs ->
                            for q <- qs,
                                do:
                                  update_in(q, ["cards"], fn cs ->
                                    Enum.map(cs, &Map.put(&1, "owner", bad))
                                  end)
                          end)
                  end)
          end)

        assert_rejected(file, "owner")
      end

      assert {:ok, _} =
               Import.run(
                 put_in(
                   good,
                   [
                     "formats",
                     Access.all(),
                     "topics",
                     Access.all(),
                     "questions",
                     Access.all(),
                     "cards",
                     Access.all(),
                     "owner"
                   ],
                   nil
                 )
               )
    end
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
    refute Map.has_key?(Map.from_struct(question), :points)
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

  describe "the backup files committed in backups/" do
    # Made before profile pictures were part of the backup: no "avatar_cards"
    # key anywhere. They must stay importable (cards come from the stub, the
    # ones it does not know are reported as missing, never fatal).
    for file <- Path.wildcard(Path.expand("../../../backups/*.json", __DIR__)) do
      @backup file

      test "#{Path.basename(file)} still imports" do
        json = File.read!(@backup)
        refute json =~ "avatar_cards"

        assert {:ok, summary} = Import.run(json, pause_ms: 0)
        assert summary.formats_failed == []
        assert summary.formats_created > 0
        assert summary.avatars == 0
        assert summary.avatars_missing == 0

        # the second time everything is skipped, nothing is overwritten
        assert {:ok, %{formats_created: 0, formats_skipped: skipped}} =
                 Import.run(json, pause_ms: 0)

        assert length(skipped) == summary.formats_created
      end
    end
  end

  test "the summary counts the profile pictures that came back and those that did not" do
    avatar_quiz()
    export = Export.build()

    # one card the stub cannot fetch
    extra = %{"password" => 424_242, "name" => "Nobody"}

    export =
      update_in(export, ["formats", Access.at(0), "avatar_cards"], &(&1 ++ [extra]))

    clear_quiz()
    assert {:ok, summary} = Import.run(export, pause_ms: 0)
    assert summary.avatars == 2
    assert summary.avatars_missing == 1
    assert [w] = summary.warnings
    assert w =~ "Nobody" and w =~ "not a profile picture"

    assert Enum.any?(
             MillenniumQuiz.Release.import_report({:ok, summary}),
             &(&1 == "Profile pictures: 2 restored, 1 missing")
           )
  end
end
