defmodule MillenniumQuizWeb.BackupLiveTest do
  # not async: the import runs in a task and writes to the shared sandbox
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  require Logger
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.Repo
  alias MillenniumQuiz.Quiz.{Export, Format}

  test "requires a login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/backup")
  end

  # The restore runs in a task of its own and reports back by message.
  defp await_result(view, selector, tries \\ 100) do
    cond do
      has_element?(view, selector) -> :ok
      tries == 0 -> flunk("#{selector} did not appear")
      true -> Process.sleep(20) && await_result(view, selector, tries - 1)
    end
  end

  defp wait_for_format(name, tries \\ 100) do
    cond do
      Repo.get_by(Format, name: name) -> :ok
      tries == 0 -> flunk("format #{name} was not restored")
      true -> Process.sleep(20) && wait_for_format(name, tries - 1)
    end
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
      await_result(view, "#restore-result #restore-summary li")

      assert Repo.get_by(Format, name: "Backed up")
    end

    test "a restore goes on when the admin leaves the page", %{conn: conn} do
      Repo.delete_all(Format)
      format_fixture(%{"name" => "Left behind"})
      json = Export.to_json()
      Repo.delete_all(Format)

      {:ok, view, _html} = live(conn, ~p"/admin/backup")

      file =
        file_input(view, "#restore-form", :backup, [
          %{name: "backup.json", content: json, type: "application/json"}
        ])

      render_upload(file, "backup.json")
      view |> form("#restore-form") |> render_submit()

      # the test environment logs warnings and above only
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: :warning) end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          view |> element("#restore-dialog-confirm") |> render_click()
          # the page goes away at once, the restore is not tied to it
          GenServer.stop(view.pid)
          wait_for_format("Left behind")
        end)

      assert Repo.get_by(Format, name: "Left behind")
      assert log =~ "Quiz restore finished"
      assert log =~ "Formats created: 1"
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
      await_result(view, "#restore-line-0")

      assert has_element?(view, "#restore-line-0", "Import failed")
    end

    test "refuses a file that is too large", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/backup")
      big = String.duplicate(" ", MillenniumQuiz.Quiz.Import.max_bytes() + 1)

      file =
        file_input(view, "#restore-form", :backup, [
          %{name: "backup.json", content: big, type: "application/json"}
        ])

      assert {:error, [[_, :too_large]]} = render_upload(file, "backup.json")
      assert has_element?(view, "#restore-button[disabled]")
    end

    test "refuses other file types", %{conn: conn} do
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
