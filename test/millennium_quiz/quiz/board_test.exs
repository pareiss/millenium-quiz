defmodule MillenniumQuiz.Quiz.BoardTest do
  use MillenniumQuiz.DataCase, async: true

  alias MillenniumQuiz.Cards.{Card, CardArtwork}
  alias MillenniumQuiz.Quiz.{Board, Question}

  @goat ~D[2005-04-01]
  @edison ~D[2010-04-24]
  @tengu ~D[2011-09-01]
  @mr3 ~D[2015-01-01]
  @mr4 ~D[2020-01-01]

  defp sample(name) do
    "test/fixtures/boards/#{name}.json" |> File.read!() |> Jason.decode!()
  end

  defp insert_card(password, attrs \\ %{}) do
    Repo.insert!(
      struct!(
        Card,
        Map.merge(
          %{
            name: "Card #{password}",
            password: password,
            frame_type: "effect",
            atk: "1800",
            def: "1000",
            level: 4,
            fetched_at: DateTime.utc_now(:second)
          },
          attrs
        )
      )
    )
  end

  defp insert_artwork(card) do
    Repo.insert!(%CardArtwork{
      card_id: card.id,
      artwork_id: card.password,
      content_type: "image/jpeg",
      data: "x",
      source_url: "https://example.test/a.jpg",
      fetched_at: DateTime.utc_now(:second)
    })
  end

  # Puts every password of the board in the pool, with `attrs_for.(code)` on top.
  defp pool_for(board, attrs_for \\ fn _ -> %{} end) do
    for code <- Board.passwords(board), do: insert_card(code, attrs_for.(code))
  end

  defp empty_player(extra) do
    Map.merge(
      %{
        "lp" => 8000,
        "monsters" => List.duplicate(nil, 5),
        "spells" => List.duplicate(nil, 5),
        "field" => nil,
        "pendulum" => [nil, nil],
        "hand" => [],
        "grave" => [],
        "banished" => [],
        "extra" => [],
        "deck" => 30
      },
      extra
    )
  end

  defp board(p1 \\ %{}, p2 \\ %{}, extra \\ %{}) do
    Map.merge(
      %{"v" => 1, "emz" => [nil, nil], "players" => [empty_player(p1), empty_player(p2)]},
      extra
    )
  end

  defp monsters(cards), do: Enum.take(cards ++ List.duplicate(nil, 5), 5)

  defp messages(issues), do: Enum.map(issues, &"#{&1.path}: #{&1.message}")

  describe "cast/1" do
    test "normalises a board: defaults for the optional zones, string keys" do
      input = %{
        v: 1,
        players: [
          %{lp: 4000, monsters: monsters([]), spells: monsters([])},
          %{lp: 4000, monsters: monsters([]), spells: monsters([])}
        ]
      }

      assert {:ok, %{"v" => 1, "emz" => [nil, nil], "players" => [p1, _]} = cast} =
               Board.cast(input)

      refute Map.has_key?(cast, "turn")

      assert %{"pendulum" => [nil, nil], "hand" => [], "deck" => 0, "field" => nil, "lp" => 4000} =
               p1
    end

    test "accepts pasted JSON" do
      assert {:ok, %{"players" => [_, _]}} = Board.cast(Jason.encode!(board()))
      assert {:error, [%{message: "is not a JSON object"}]} = Board.cast("[1")
    end

    test "the research samples are valid" do
      for name <- ~w(alphakretin_01 alphakretin_03_overlay alphakretin_12a_emz tutorial_pendulum) do
        assert {:ok, _} = Board.cast(sample(name)), name
      end
    end

    test "names the field in every shape error" do
      cases = [
        {%{"v" => 2}, "board v: must be 1"},
        {%{"turn" => 0}, "board turn: must be an integer of 1 or more"},
        {%{"phase" => "dinner"}, "board phase: must be one of"},
        {%{"turnPlayer" => 3}, "board turn player: must be 1 or 2"},
        {%{"colour" => "red"}, "board: has an unknown key \"colour\""},
        {%{"players" => []}, "board players: must be a list of exactly 2 players"},
        {%{"emz" => [nil]}, "board extra monster zones: must have exactly 2 slots"}
      ]

      for {extra, expected} <- cases do
        assert {:error, issues} = Board.cast(board(%{}, %{}, extra))
        assert Enum.any?(messages(issues), &String.starts_with?(&1, expected)), expected
      end
    end

    test "player and card errors name the player and the zone" do
      p1 = %{
        "lp" => 100_000,
        "deck" => -1,
        "monsters" => [nil, nil, %{"code" => 1, "pos" => "up"}, nil],
        "spells" => monsters([]) |> List.replace_at(4, %{"pos" => "set"}),
        "hand" => [nil, %{"code" => "x"}],
        "grave" => %{},
        "pendulum" => [nil, nil, nil]
      }

      assert {:error, issues} = Board.cast(board(p1))
      msgs = messages(issues)

      assert "player 1 lp: must be a whole number from 0 to 99999" in msgs
      assert "player 1 deck: must be a count of 0 or more" in msgs

      assert "player 1 monster zones: must have exactly 5 slots (use null for an empty one)" in msgs

      assert "player 1 spell/trap zone 5: has no code" in msgs
      assert "player 1 hand card 1: must be a card, not null" in msgs
      assert "player 1 hand card 2: code must be a positive whole number (the password)" in msgs
      assert "player 1 graveyard card: must be a list of cards" in msgs

      assert "player 1 pendulum zones: must have exactly 2 slots (use null for an empty one)" in msgs
    end

    test "card errors: position, overlay, counters, equip" do
      bad = %{
        "code" => 5,
        "pos" => "up",
        "overlay" => ["a"],
        "counters" => 0,
        "equip" => %{"p" => 3, "m" => 1}
      }

      assert {:error, issues} = Board.cast(board(%{"monsters" => monsters([nil, bad])}))

      msgs = messages(issues)
      assert "player 1 monster zone 2: pos must be one of atk, def, set" in msgs
      assert "player 1 monster zone 2: overlay must be a list of passwords" in msgs
      assert Enum.any?(msgs, &String.contains?(&1, "counters must be a count"))
      assert Enum.any?(msgs, &String.contains?(&1, "equip must be"))
    end

    test "LP is 0 to 99999" do
      assert {:ok, _} = Board.cast(board(%{"lp" => 0}, %{"lp" => 99_999}))
      assert {:error, [%{path: "player 2 lp"}]} = Board.cast(board(%{}, %{"lp" => -1}))
      assert {:error, [%{path: "player 1 lp"}]} = Board.cast(board(%{"lp" => 100_000}))
    end

    test "a sample with LP over 99999 is rejected" do
      sample = put_in(sample("alphakretin_12a_emz"), ["players", Access.at(1), "lp"], 5_803_600)
      assert {:error, [%{path: "player 2 lp"}]} = Board.cast(sample)
    end
  end

  describe "validate/2" do
    test "ok for a board whose cards are in the pool and old enough" do
      b = board(%{"monsters" => monsters([%{"code" => 111, "pos" => "atk"}])})
      pool_for(b, fn _ -> %{tcg_release_date: ~D[2002-03-08]} end)
      assert :ok = Board.validate(b, @goat)
    end

    test "cards missing from the pool are listed with their passwords" do
      b =
        board(%{
          "monsters" => monsters([%{"code" => 111}]),
          "hand" => [%{"code" => 222}],
          "extra" => [%{"code" => 222}]
        })

      insert_card(111)
      assert {:error, issues} = Board.validate(b, @goat)
      assert Board.missing_passwords(issues) == [222]
      assert "player 1 hand card 1: card 222 is not in the card pool" in messages(issues)
    end

    test "a card released after the format's date is rejected, one without a date is not" do
      b =
        board(%{
          "monsters" => monsters([%{"code" => 111}, %{"code" => 112}]),
          "grave" => [%{"code" => 113}]
        })

      insert_card(111, %{tcg_release_date: ~D[2005-04-01]})
      insert_card(112, %{tcg_release_date: ~D[2005-04-02], name: "Newcomer"})
      insert_card(113, %{tcg_release_date: nil})

      assert {:error, [issue]} = Board.validate(b, @goat)
      assert issue.kind == :not_released
      assert issue.path == "player 1 monster zone 2"

      assert issue.message ==
               "Newcomer (112) was released on 2005-04-02, after the format's date 2005-04-01"

      # a format without a date, or a bare rule, does not check release dates
      assert :ok = Board.validate(b, nil)
      assert :ok = Board.validate(b, :mr4)
    end

    test "Extra Monster Zones only under Master Rule 4" do
      b = board(%{}, %{}, %{"emz" => [%{"code" => 111, "pos" => "atk"}, nil]})
      insert_card(111)

      for date <- [@goat, @edison, @tengu, ~D[2013-12-31], @mr3, ~D[2017-03-31]] do
        assert {:error, [%{kind: :zone, path: "extra monster zone 1", message: msg}]} =
                 Board.validate(b, date)

        assert msg =~ "do not exist under Master Rule"
      end

      assert :ok = Board.validate(b, ~D[2017-04-01])
      assert :ok = Board.validate(b, @mr4)
    end

    test "pendulum scales from Master Rule 3" do
      b = board(%{"pendulum" => [%{"code" => 111}, nil]})
      insert_card(111)

      assert {:error, [%{kind: :zone, path: "player 1 pendulum zone 1"}]} =
               Board.validate(b, ~D[2013-12-31])

      assert :ok = Board.validate(b, ~D[2014-01-01])
      assert :ok = Board.validate(b, @mr4)
    end

    test "a scale and a spell cannot share the outer spell/trap zone" do
      insert_card(111)
      insert_card(112)
      scale = %{"code" => 111}
      spell = %{"code" => 112}

      left = board(%{"pendulum" => [scale, nil], "spells" => monsters([spell])})

      right =
        board(%{"pendulum" => [nil, scale], "spells" => monsters([nil, nil, nil, nil, spell])})

      middle = board(%{"pendulum" => [scale, nil], "spells" => monsters([nil, spell])})

      assert {:error, [%{path: "player 1 spell/trap zone 1", message: m}]} =
               Board.validate(left, @mr3)

      assert m =~ "left Pendulum Zone"
      assert {:error, [%{path: "player 1 spell/trap zone 5"}]} = Board.validate(right, @mr3)
      assert :ok = Board.validate(middle, @mr3)
    end

    test "overlay units need a monster on the field, an Xyz Monster and the Xyz era" do
      xyz = %{"code" => 111, "overlay" => [112, 112]}
      b = board(%{"monsters" => monsters([xyz])})
      insert_card(111, %{frame_type: "xyz"})
      insert_card(112)

      assert :ok = Board.validate(b, @tengu)
      assert :ok = Board.validate(b, @mr4)

      assert {:error, [%{kind: :zone, message: msg}]} = Board.validate(b, @edison)
      assert msg =~ "did not exist on the format's date"

      spell = board(%{"spells" => monsters([xyz])})

      assert {:error, [%{message: "only a monster on the field can have overlay units"}]} =
               Board.validate(spell, @tengu)
    end

    test "overlay on another monster type is rejected, an unknown frame is let through" do
      b =
        board(%{
          "monsters" =>
            monsters([
              %{"code" => 111, "overlay" => [112]},
              %{"code" => 113, "overlay" => [112]}
            ])
        })

      insert_card(111, %{frame_type: "synchro", name: "Not Xyz"})
      insert_card(112)
      insert_card(113, %{frame_type: nil})

      assert {:error, [%{path: "player 1 monster zone 1", message: msg}]} =
               Board.validate(b, @mr4)

      assert msg == "Not Xyz is not an Xyz Monster, so it cannot have overlay units"
    end

    test "overlay materials must be in the pool and released too" do
      b = board(%{"monsters" => monsters([%{"code" => 111, "overlay" => [998, 112]}])})
      insert_card(111, %{frame_type: "xyz"})
      insert_card(112, %{tcg_release_date: ~D[2020-01-01]})

      assert {:error, issues} = Board.validate(b, @tengu)
      assert Board.missing_passwords(issues) == [998]

      assert Enum.any?(
               issues,
               &(&1.kind == :not_released and &1.path == "player 1 monster zone 1 overlay unit 2")
             )
    end
  end

  describe "the research samples" do
    test "Goat-style board (hand, set backrow, extra deck) validates and resolves" do
      # the research board has a scale in player 2's pendulum zone; Goat has none
      sample = put_in(sample("alphakretin_01"), ["players", Access.at(1), "pendulum"], [nil, nil])
      pool_for(sample, fn _ -> %{tcg_release_date: ~D[2004-01-01]} end)
      assert {:ok, board} = Board.cast(sample)
      assert :ok = Board.validate(board, @goat)

      assert %{"rule" => "mr1_2", "players" => [p1, p2]} = Board.resolve(board, @goat)
      assert p1["lp"] == 1 and p2["lp"] == 500
      assert length(p1["hand"]) == 3 and length(p1["extra"]) == 11
      assert [%{"pos" => "set"}, %{"pos" => "set"}, nil, nil, nil] = p1["spells"]
    end

    test "board with an Xyz monster holding 28 overlay units" do
      sample = sample("alphakretin_03_overlay")
      pool_for(sample, fn code -> if code == 33_776_843, do: %{frame_type: "xyz"}, else: %{} end)
      assert {:ok, board} = Board.cast(sample)
      assert :ok = Board.validate(board, @mr4)
      assert {:error, _} = Board.validate(board, @edison)

      assert %{"players" => [_, p2]} = Board.resolve(board, @mr4)

      assert [_, _, %{"overlay" => 28, "kind" => "xyz", "atk" => 19_300}, _, _] =
               p2["monsters"]
    end

    test "board with an Extra Monster Zone" do
      sample = sample("alphakretin_12a_emz")
      pool_for(sample)
      assert {:ok, board} = Board.cast(sample)
      assert :ok = Board.validate(board, @mr4)
      assert {:error, [%{kind: :zone} | _]} = Board.validate(board, @mr3)

      assert %{"emz" => [%{"password" => 7_778_726, "atk" => 3400}, nil]} =
               Board.resolve(board, @mr4)
    end

    test "board with a Pendulum scale" do
      sample = sample("tutorial_pendulum")
      pool_for(sample)
      assert {:ok, board} = Board.cast(sample)
      assert :ok = Board.validate(board, @mr3)
      assert {:error, _} = Board.validate(board, @tengu)

      assert %{"players" => [p1, _]} = Board.resolve(board, @mr3)
      assert [_, _, _, _, %{"scale" => true, "password" => 20_409_757}] = p1["spells"]
    end
  end

  describe "resolve/3" do
    test "maps cards from the pool: kind, stats, position, counters, art, in one query" do
      art_card =
        insert_card(1, %{name: "Dragon", frame_type: "effect", level: 7, atk: "2400", def: "2000"})

      insert_artwork(art_card)
      insert_card(2, %{name: "Fusion", frame_type: "fusion", atk: "?"})
      insert_card(3, %{name: "Link", frame_type: "link", level: nil, atk: "2300", def: nil})
      insert_card(4, %{name: "Scale", frame_type: "normal_pendulum", pendulum_scale: 1})

      insert_card(5, %{
        name: "Mirror",
        frame_type: "trap",
        kind: "Trap",
        atk: nil,
        def: nil,
        level: nil
      })

      insert_card(6, %{
        name: "Old",
        frame_type: nil,
        kind: "Spell",
        card_type: "Normal Spell",
        atk: nil,
        def: nil,
        level: nil
      })

      b =
        board(
          %{
            "lp" => 4000,
            "monsters" =>
              monsters([
                %{
                  "code" => 1,
                  "pos" => "def",
                  "counters" => [%{"type" => 1, "count" => 2}, %{"type" => 2, "count" => 1}]
                },
                %{"code" => 2},
                %{"code" => 3, "pos" => "set"}
              ]),
            "spells" => monsters([nil, %{"code" => 5, "pos" => "set"}]),
            "pendulum" => [%{"code" => 4}, nil],
            "field" => %{"code" => 6, "pos" => "up"},
            "hand" => [%{"code" => 2}, %{"code" => 2}],
            "deck" => 12
          },
          %{},
          %{"turn" => 3, "phase" => "battle", "turnPlayer" => 2}
        )

      {queries, resolved} = count_queries(fn -> Board.resolve(b, @mr3) end)
      assert queries == 1

      assert %{
               "rule" => "mr3",
               "turn" => 3,
               "phase" => "battle",
               "turn_player" => 2,
               "emz" => [nil, nil],
               "players" => [p1, p2]
             } = resolved

      assert p1["lp"] == 4000 and p1["deck"] == 12
      assert [dragon, fusion, link, nil, nil] = p1["monsters"]

      assert dragon == %{
               "name" => "Dragon",
               "kind" => "effect",
               "atk" => 2400,
               "def" => 2000,
               "level" => 7,
               "pos" => "def",
               "overlay" => 0,
               "counters" => 3,
               "art" => "/cards/#{art_card.id}/artwork?w=200",
               "scale" => false,
               "password" => 1
             }

      assert %{"kind" => "fusion", "atk" => nil, "art" => nil, "pos" => "atk"} = fusion

      assert %{"kind" => "link", "level" => nil, "def" => nil, "atk" => 2300, "pos" => "set"} =
               link

      assert [
               %{"scale" => true, "kind" => "pendulum"},
               %{"kind" => "trap", "pos" => "set", "atk" => nil, "level" => nil},
               nil,
               nil,
               nil
             ] = p1["spells"]

      assert %{"kind" => "spell", "pos" => "atk", "name" => "Old"} = p1["field"]
      assert [%{"password" => 2}, %{"password" => 2}] = p1["hand"]
      assert p2["monsters"] == List.duplicate(nil, 5)
      assert p2["field"] == nil and p2["grave"] == [] and p2["lp"] == 8000

      # a game stores it as JSON
      assert resolved == resolved |> Jason.encode!() |> Jason.decode!()
    end

    test "art width option" do
      card = insert_card(1)
      insert_artwork(card)
      b = board(%{"monsters" => monsters([%{"code" => 1}])})

      assert %{"players" => [%{"monsters" => [%{"art" => art} | _]}, _]} =
               Board.resolve(b, :mr4, art_width: 400)

      assert art == "/cards/#{card.id}/artwork?w=400"

      assert %{"players" => [%{"monsters" => [%{"art" => full} | _]}, _]} =
               Board.resolve(b, :mr4, art_width: nil)

      assert full == "/cards/#{card.id}/artwork"
    end

    test "overrides the printed ATK and DEF with the stored ones" do
      insert_card(1, %{atk: "1000", def: "500"})
      b = board(%{"monsters" => monsters([%{"code" => 1, "atk" => 3000}])})

      assert %{"players" => [%{"monsters" => [%{"atk" => 3000, "def" => 500} | _]}, _]} =
               Board.resolve(b, :mr3)
    end

    test "a card missing from the pool becomes the Unknown card placeholder" do
      b =
        board(%{
          "monsters" => monsters([%{"code" => 777, "pos" => "def", "overlay" => [1, 2]}]),
          "spells" => monsters([nil, %{"code" => 778, "pos" => "set"}]),
          "hand" => [%{"code" => 779}]
        })

      assert %{"players" => [p1, _]} = Board.resolve(b, :mr4)

      assert [
               %{
                 "name" => "Unknown card",
                 "password" => 777,
                 "kind" => "normal",
                 "pos" => "def",
                 "overlay" => 2,
                 "atk" => nil,
                 "art" => nil,
                 "scale" => false,
                 "counters" => 0
               },
               nil,
               nil,
               nil,
               nil
             ] = p1["monsters"]

      assert [
               nil,
               %{"name" => "Unknown card", "kind" => "spell", "password" => 778},
               nil,
               nil,
               nil
             ] =
               p1["spells"]

      assert [%{"name" => "Unknown card", "password" => 779}] = p1["hand"]
    end

    test "takes a rule key or a date, and nil is no board" do
      assert Board.resolve(board(), @goat)["rule"] == "mr1_2"
      assert Board.resolve(board(), ~D[2017-04-01])["rule"] == "mr4"
      assert Board.resolve(board(), :mr3)["rule"] == "mr3"
      assert Board.resolve(nil, :mr3) == nil
    end
  end

  describe "Question.changeset/2" do
    defp question_attrs(extra) do
      Map.merge(
        %{
          "text" => "What happens?",
          "choices" => %{
            "0" => %{"text" => "A", "correct" => true},
            "1" => %{"text" => "B", "correct" => false}
          }
        },
        extra
      )
    end

    test "casts a valid board and normalises it" do
      cs = Question.changeset(%Question{}, question_attrs(%{"board" => board()}))
      assert cs.valid?
      assert %{"v" => 1, "players" => [_, _]} = Ecto.Changeset.get_field(cs, :board)
    end

    test "a board as JSON text or under an atom key is accepted" do
      cs = Question.changeset(%Question{}, question_attrs(%{"board" => Jason.encode!(board())}))
      assert cs.valid?

      attrs = %{
        text: "What happens?",
        choices: %{
          "0" => %{"text" => "A", "correct" => true},
          "1" => %{"text" => "B", "correct" => false}
        },
        board: board()
      }

      cs = Question.changeset(%Question{}, attrs)
      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :board)
    end

    test "an invalid board is an error on :board that names the zone" do
      bad = board(%{"monsters" => monsters([nil, nil, %{"code" => 1, "pos" => "up"}])})
      cs = Question.changeset(%Question{}, question_attrs(%{"board" => bad}))
      refute cs.valid?
      assert {"player 1 monster zone 3: pos must be one of atk, def, set", _} = cs.errors[:board]
    end

    test "a missing board key keeps the board, an empty value removes it" do
      existing = %Question{board: board()}
      cs = Question.changeset(existing, question_attrs(%{}))
      assert cs.valid?
      refute Map.has_key?(cs.changes, :board)

      cs = Question.changeset(existing, question_attrs(%{"board" => ""}))
      assert cs.changes.board == nil
      cs = Question.changeset(existing, question_attrs(%{"board" => nil}))
      assert cs.changes.board == nil
    end

    test "validate_board_for_format/2 adds the format errors" do
      insert_card(111)

      b =
        board(%{"monsters" => monsters([%{"code" => 111}, %{"code" => 999}])}, %{}, %{
          "emz" => [%{"code" => 111}, nil]
        })

      cs =
        %Question{}
        |> Question.changeset(question_attrs(%{"board" => b}))
        |> Question.validate_board_for_format(@goat)

      refute cs.valid?
      msgs = for {:board, {msg, _}} <- cs.errors, do: msg
      assert "player 1 monster zone 2: card 999 is not in the card pool" in msgs

      assert Enum.any?(
               msgs,
               &String.starts_with?(
                 &1,
                 "extra monster zone 1: the Extra Monster Zones do not exist"
               )
             )

      no_board =
        %Question{}
        |> Question.changeset(question_attrs(%{}))
        |> Question.validate_board_for_format(@goat)

      assert no_board.valid?
    end

    test "a board is stored and read back" do
      format = MillenniumQuiz.QuizFixtures.format_fixture()
      topic = hd(format.topics)

      {:ok, question} =
        MillenniumQuiz.Quiz.create_question(topic, question_attrs(%{"board" => board()}))

      assert %{"v" => 1} = Repo.reload!(question).board
    end
  end

  defp count_queries(fun) do
    ref = make_ref()
    me = self()

    :telemetry.attach(
      inspect(ref),
      [:millennium_quiz, :repo, :query],
      fn _, _, _, _ -> if self() == me, do: send(me, {ref, :query}) end,
      nil
    )

    result = fun.()
    :telemetry.detach(inspect(ref))
    {drain(ref, 0), result}
  end

  defp drain(ref, n) do
    receive do
      {^ref, :query} -> drain(ref, n + 1)
    after
      0 -> n
    end
  end
end
