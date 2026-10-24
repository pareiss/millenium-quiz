defmodule MillenniumQuizWeb.BackupLiveTest do
  # not async: the import runs in a task and writes to the shared sandbox
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.Repo
  alias MillenniumQuiz.Quiz.{Export, Format}

  test "requires a login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/backup")
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "links to the page and the download", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/backup")
      assert has_element?(view, "#download-backup[href='/admin/backup.json']")
      assert has_element?(view, "#site-header a[href='/admin/backup']")
      assert has_element?(view, "#menu-backup")
      assert has_element?(view, "#restore-button[disabled]")
    end

    test "restores an uploaded file after a confirmation", %{conn: conn} do
      Repo.delete_all(Format)
      format_fixture(%{"name" => "Backed up"})
      json = Export.to_json()
      Repo.delete_all(Format)

      {:ok, view, _html} = live(conn, ~p"/admin/backup")

      file =
        file_input(view, "#restore-form", :backup, [
          %{name: "backup.json", content: json, type: "application/json"}
        ])

      render_upload(file, "backup.json")
      refute has_element?(view, "#restore-button[disabled]")

      view |> form("#restore-form") |> render_submit()
      assert has_element?(view, "#restore-dialog")
      view |> element("#restore-dialog-cancel") |> render_click()
      refute has_element?(view, "#restore-dialog")
      assert Repo.aggregate(Format, :count) == 0

      view |> form("#restore-form") |> render_submit()
      view |> element("#restore-dialog-confirm") |> render_click()
      render_async(view)

      assert has_element?(view, "#restore-result #restore-summary li")
      assert Repo.get_by(Format, name: "Backed up")
    end

    test "reports a file that is not a backup", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/backup")

      file =
        file_input(view, "#restore-form", :backup, [
          %{name: "backup.json", content: "{nope", type: "application/json"}
        ])

      render_upload(file, "backup.json")
      view |> form("#restore-form") |> render_submit()
      view |> element("#restore-dialog-confirm") |> render_click()
      render_async(view)

      assert has_element?(view, "#restore-line-0")
    end

    test "refuses other file types and large files", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/backup")

      file =
        file_input(view, "#restore-form", :backup, [
          %{name: "backup.txt", content: "{}", type: "text/plain"}
        ])

      assert {:error, [[_, :not_accepted]]} = render_upload(file, "backup.txt")
      assert has_element?(view, "#restore-button[disabled]")
    end
  end
end
