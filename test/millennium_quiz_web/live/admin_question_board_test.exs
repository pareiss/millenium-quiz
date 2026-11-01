defmodule MillenniumQuizWeb.AdminQuestionBoardTest do
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{Quiz, Repo}
  alias MillenniumQuiz.Cards.Card

  setup :register_and_log_in_user

  setup do
    format = format_fixture()
    topic = hd(format.topics)
    insert_card(111)
    %{topic: topic}
  end

  defp insert_card(password, attrs \\ %{}) do
    Repo.insert!(
      struct!(
        Card,
        Map.merge(
          %{
            name: "Test Dragon",
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

  defp board(code \\ 111) do
    player = %{
      "lp" => 8000,
      "monsters" => [%{"code" => code, "pos" => "atk"}, nil, nil, nil, nil],
      "spells" => List.duplicate(nil, 5)
    }

    %{"v" => 1, "turn" => 2, "phase" => "main1", "players" => [player, player]}
  end

  defp params(board_json, text \\ "What is on the board?") do
    %{question: %{text: text, board: board_json, choices: choices_params(~w(a b c d))}}
  end

  defp new_form(conn, topic) do
    {:ok, view, _} = live(conn, ~p"/admin/topics/#{topic.id}/questions/new")
    view
  end

  defp questions(topic),
    do: Quiz.get_format!(topic.format_id).topics |> hd() |> Map.fetch!(:questions)

  test "a new question has an empty board section", %{conn: conn, topic: topic} do
    view = new_form(conn, topic)
    assert has_element?(view, "#board-section")
    assert has_element?(view, "textarea#question_board")
    assert has_element?(view, "#board-status", "No board.")
    refute has_element?(view, "#board-preview-button")
    assert has_element?(view, "#toggle-board-section[aria-expanded=false]")
    assert has_element?(view, "#remove-board[disabled]")
  end

  test "a valid board shows as valid, has a preview and is saved cast", %{
    conn: conn,
    topic: topic
  } do
    view = new_form(conn, topic)
    json = Jason.encode!(board())

    view |> form("#question-form", params(json)) |> render_change()
    assert has_element?(view, "#board-valid", "Valid for")
    assert has_element?(view, "#board-preview-button", "Board")
    assert has_element?(view, "#board-preview-button-note", "Turn 2")
    assert has_element?(view, "#board-section .badge", "attached")

    view |> form("#question-form", params(json)) |> render_submit()
    assert_redirect(view)

    [q] = questions(topic)
    assert %{"v" => 1, "reveal_all" => false, "players" => [_, _]} = q.board
  end

  test "reveal_all is kept", %{conn: conn, topic: topic} do
    view = new_form(conn, topic)
    json = Jason.encode!(Map.put(board(), "reveal_all", true))
    view |> form("#question-form", params(json)) |> render_submit()
    assert_redirect(view)
    [q] = questions(topic)
    assert q.board["reveal_all"] == true
  end

  test "the preview opens and closes", %{conn: conn, topic: topic} do
    view = new_form(conn, topic)
    view |> form("#question-form", params(Jason.encode!(board()))) |> render_change()

    refute has_element?(view, "#board-preview")
    view |> element("#board-preview-button") |> render_click()
    assert has_element?(view, "#board-preview[role=dialog]")
    refute has_element?(view, "#question-form #board-preview")

    view |> element("#board-preview-tile-p1-monsters-0") |> render_click()
    assert has_element?(view, "#board-preview-detail", "Test Dragon")

    view |> element("#board-preview-close") |> render_click()
    refute has_element?(view, "#board-preview")
  end

  test "a board of the wrong shape shows its issues; saving leaves it out", %{
    conn: conn,
    topic: topic
  } do
    view = new_form(conn, topic)
    bad = board() |> Map.put("phase", "dinner") |> Map.put("turn", 0) |> Jason.encode!()

    view |> form("#question-form", params(bad)) |> render_change()
    assert has_element?(view, "#board-issues", "board turn")
    assert has_element?(view, "#board-issues", "board phase")
    assert has_element?(view, "#board-unsaved")
    refute has_element?(view, "#board-valid")
    refute has_element?(view, "#board-preview-button")

    view |> form("#question-form", params(bad)) |> render_submit()
    {path, flash} = assert_redirect(view)
    assert path =~ "/admin/formats/"
    assert flash["error"] =~ "board was not"
    assert [%{board: nil}] = questions(topic)

    view = new_form(conn, topic)
    view |> form("#question-form", params("{not json")) |> render_change()
    assert has_element?(view, "#board-issues")
  end

  test "editing with a broken board keeps the stored board", %{conn: conn, topic: topic} do
    q = question_fixture(topic, %{"board" => board()})
    stored = Quiz.get_question!(q.id).board
    {:ok, view, _} = live(conn, ~p"/admin/questions/#{q.id}/edit")

    view
    |> form("#question-form", %{question: %{text: "Edited?", board: "{oops"}})
    |> render_submit()

    {_path, flash} = assert_redirect(view)
    assert flash["error"] =~ "board was not"
    updated = Quiz.get_question!(q.id)
    assert updated.text == "Edited?"
    assert updated.board == stored
  end

  test "a board that casts but does not fit the date is saved with a warning", %{
    conn: conn,
    topic: topic
  } do
    view = new_form(conn, topic)
    json = Jason.encode!(board(999))

    view |> form("#question-form", params(json)) |> render_submit()
    {_path, flash} = assert_redirect(view)
    assert flash["info"] =~ "board has problems"
    assert [%{board: %{"players" => [_, _]}}] = questions(topic)
  end

  test "cards missing from the pool are reported, at most a handful of issues", %{
    conn: conn,
    topic: topic
  } do
    view = new_form(conn, topic)

    player = fn code ->
      %{
        "lp" => 8000,
        "monsters" => List.duplicate(%{"code" => code}, 5),
        "spells" => List.duplicate(nil, 5)
      }
    end

    json = Jason.encode!(%{"v" => 1, "players" => [player.(999), player.(111)]})
    view |> form("#question-form", params(json)) |> render_change()

    assert has_element?(view, "#board-issues", "5 problems")
    assert has_element?(view, "#board-issues", "player 1 monster zone 1")
    assert has_element?(view, "#board-missing", "999")
    refute has_element?(view, "#board-valid")

    many = Jason.encode!(%{"v" => 1, "players" => [player.(999), player.(998)]})
    view |> form("#question-form", params(many)) |> render_change()
    assert has_element?(view, "#board-issues", "10 problems")
    assert has_element?(view, "#board-issues", "and 5 more")
    assert has_element?(view, "#board-issues li", "player 1 monster zone 5")
    refute has_element?(view, "#board-issues li", "player 2 monster zone 1")
  end

  test "a card released after the format's date is reported", %{conn: conn, topic: topic} do
    insert_card(222, %{tcg_release_date: ~D[2020-01-01]})
    view = new_form(conn, topic)
    view |> form("#question-form", params(Jason.encode!(board(222)))) |> render_change()
    assert has_element?(view, "#board-issues", "2 problems")
  end

  test "remove board clears the text, the preview and the stored board", %{
    conn: conn,
    topic: topic
  } do
    q = question_fixture(topic, %{"board" => board()})
    {:ok, view, _} = live(conn, ~p"/admin/questions/#{q.id}/edit")

    assert has_element?(view, "#toggle-board-section[aria-expanded=true]")
    assert has_element?(view, "#board-preview-button")
    view |> element("#remove-board") |> render_click()
    assert has_element?(view, "#board-status", "No board.")
    refute has_element?(view, "#board-preview-button")

    view |> form("#question-form", %{question: %{text: "Still here?"}}) |> render_submit()
    assert_redirect(view)
    assert Quiz.get_question!(q.id).board == nil
  end

  test "editing a question keeps its board when the section is untouched", %{
    conn: conn,
    topic: topic
  } do
    q = question_fixture(topic, %{"board" => board()})
    stored = Quiz.get_question!(q.id).board
    {:ok, view, _} = live(conn, ~p"/admin/questions/#{q.id}/edit")

    assert has_element?(view, "#board-valid")
    view |> form("#question-form", %{question: %{text: "A new text?"}}) |> render_submit()
    assert_redirect(view)

    updated = Quiz.get_question!(q.id)
    assert updated.text == "A new text?"
    assert updated.board == stored
  end

  test "the section can be collapsed and opened", %{conn: conn, topic: topic} do
    view = new_form(conn, topic)
    view |> element("#toggle-board-section") |> render_click()
    assert has_element?(view, "#toggle-board-section[aria-expanded=true]")
    assert has_element?(view, "#board-section-body:not([hidden])")
    view |> element("#toggle-board-section") |> render_click()
    assert has_element?(view, "#board-section-body[hidden]")
    assert has_element?(view, "textarea#question_board")
  end
end
