defmodule MillenniumQuiz.BoardGameFixtures do
  @moduledoc """
  A playable format whose first question has a board, for the tests of games
  that carry one (`Games`, `GameLive`). The format's date is 2005-04-01, so the
  board has the zones of the Master Rule 1/2.
  """

  alias MillenniumQuiz.Cards.Card
  alias MillenniumQuiz.Quiz.Question
  alias MillenniumQuiz.Repo

  import MillenniumQuiz.QuizFixtures

  # passwords of the cards in the pool
  @p1_up 1001
  @p1_down 1002
  @p1_trap 1003
  @hand 1004
  @p2_up 1005
  @p2_down 1006
  @field 1007
  @extra 1008
  # on the board, but not in the pool
  @missing 9_999_999

  def codes,
    do: %{
      p1_up: @p1_up,
      p1_down: @p1_down,
      p1_trap: @p1_trap,
      hand: @hand,
      p2_up: @p2_up,
      p2_down: @p2_down,
      field: @field,
      extra: @extra,
      missing: @missing
    }

  def stored_board(extra \\ %{}) do
    nils = List.duplicate(nil, 5)

    player = fn lp, attrs ->
      Map.merge(
        %{
          "lp" => lp,
          "monsters" => nils,
          "spells" => nils,
          "field" => nil,
          "hand" => [],
          "grave" => [],
          "banished" => [],
          "extra" => [],
          "deck" => 20
        },
        attrs
      )
    end

    Map.merge(
      %{
        "v" => 1,
        "turn" => 3,
        "phase" => "main1",
        "turnPlayer" => 1,
        "emz" => [nil, nil],
        "players" => [
          player.(6200, %{
            "monsters" => [
              nil,
              %{"code" => @p1_up},
              %{"code" => @p1_down, "pos" => "set"},
              nil,
              nil
            ],
            "spells" => [nil, nil, %{"code" => @p1_trap, "pos" => "set"}, nil, nil],
            "hand" => [%{"code" => @hand}],
            "grave" => [%{"code" => @hand}, %{"code" => @missing}]
          }),
          player.(5400, %{
            "monsters" => [
              %{"code" => @p2_up},
              nil,
              nil,
              %{"code" => @p2_down, "pos" => "set"},
              nil
            ],
            "field" => %{"code" => @field},
            "extra" => [%{"code" => @extra}]
          })
        ]
      },
      extra
    )
  end

  def insert_card(password, attrs \\ %{}) do
    Repo.insert!(
      struct!(
        Card,
        Map.merge(
          %{
            name: "Board Card #{password}",
            password: password,
            frame_type: "effect",
            kind: "Monster",
            monster_type_line: "Warrior / Effect",
            attribute: "DARK",
            atk: "1800",
            def: "1000",
            level: 4,
            texts: %{"en" => "Text of card #{password}."},
            fetched_at: DateTime.utc_now(:second)
          },
          attrs
        )
      )
    )
  end

  @doc """
  A playable format (2 topics, 2 questions each) whose first question has the
  `stored_board/0`. Returns `%{format: format, question: question, board: board}`.
  """
  def board_format_fixture(board \\ stored_board()) do
    for code <- [@p1_up, @p1_down, @p1_trap, @hand, @p2_up, @p2_down, @field, @extra],
        do: insert_card(code)

    format = playable_format_fixture(2)
    question = format |> Map.fetch!(:topics) |> hd() |> Map.fetch!(:questions) |> hd()

    question =
      question |> Ecto.Changeset.change(board: board) |> Repo.update!() |> Repo.preload(:topic)

    %{format: format, question: %Question{} = question, board: board}
  end
end
