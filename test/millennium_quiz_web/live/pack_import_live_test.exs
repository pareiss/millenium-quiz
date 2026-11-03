defmodule MillenniumQuizWeb.PackImportLiveTest do
  # not async: the import runs in a task and writes to the shared sandbox
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.Quiz

  test "requires a login", %{conn: conn} do
    format = format_fixture()

    assert {:error, {:redirect, %{to: "/admin/login"}}} =
             live(conn, ~p"/admin/formats/#{format}/pack")
  end

  defp await_result(view, selector, tries \\ 100) do
    cond do
      has_element?(view, selector) -> :ok
      tries == 0 -> flunk("#{selector} did not appear")
      true -> Process.sleep(20) && await_result(view, selector, tries - 1)
    end
  end

  defp upload(view, content) do
    file =
      file_input(view, "#pack-form", :pack, [
        %{name: "pack.json", content: content, type: "application/json"}
      ])

    render_upload(file, "pack.json")
    view |> form("#pack-form") |> render_submit()
    view |> element("#pack-dialog-confirm") |> render_click()
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "the format page links to the import page", %{conn: conn} do
      format = format_fixture()
      {:ok, view, _} = live(conn, ~p"/admin/formats/#{format}")
      assert has_element?(view, "#import-pack[href='/admin/formats/#{format.id}/pack']")
      {:ok, view, _} = live(conn, ~p"/admin/formats/#{format}/pack")
      assert has_element?(view, "#pack-button[disabled]")
    end

    test "imports a pack after a confirmation and lists the failures", %{conn: conn} do
      format = format_fixture(%{"name" => "Pack target"})

      pack = %{
        "version" => 1,
        "credits" => "Made by tests",
        "topics" => [
          %{
            "name" => "Puzzle",
            "questions" => [
              %{
                "text" => "Good?",
                "choices" => [
                  %{"text" => "Yes", "correct" => true},
                  %{"text" => "No", "correct" => false}
                ]
              },
              %{"text" => "Broken"}
            ]
          }
        ]
      }

      {:ok, view, _} = live(conn, ~p"/admin/formats/#{format}/pack")

      file =
        file_input(view, "#pack-form", :pack, [
          %{name: "pack.json", content: Jason.encode!(pack), type: "application/json"}
        ])

      render_upload(file, "pack.json")
      view |> form("#pack-form") |> render_submit()
      assert has_element?(view, "#pack-dialog")
      view |> element("#pack-dialog-cancel") |> render_click()
      refute has_element?(view, "#pack-dialog")
      assert Quiz.questions_for_format(format.id) == []

      view |> form("#pack-form") |> render_submit()
      view |> element("#pack-dialog-confirm") |> render_click()
      await_result(view, "#pack-result #pack-line-0")

      assert has_element?(view, "#pack-line-0", "imported: 1")
      assert has_element?(view, "#pack-summary li", "Failed: Puzzle, question 2")
      assert has_element?(view, "#pack-credits", "Made by tests")
      assert has_element?(view, "#pack-back[href='/admin/formats/#{format.id}']")
      assert [%{text: "Good?"}] = Quiz.questions_for_format(format.id)
    end

    test "says why a file is not a pack", %{conn: conn} do
      format = format_fixture()
      {:ok, view, _} = live(conn, ~p"/admin/formats/#{format}/pack")
      upload(view, "{nope")
      await_result(view, "#pack-error")
      assert has_element?(view, "#pack-error", "not valid JSON")
      refute has_element?(view, "#pack-result")
    end

    test "refuses other file types", %{conn: conn} do
      format = format_fixture()
      {:ok, view, _} = live(conn, ~p"/admin/formats/#{format}/pack")

      file =
        file_input(view, "#pack-form", :pack, [
          %{name: "pack.txt", content: "{}", type: "text/plain"}
        ])

      assert {:error, [[_, :not_accepted]]} = render_upload(file, "pack.txt")
      assert has_element?(view, "#pack-button[disabled]")
    end
  end
end
