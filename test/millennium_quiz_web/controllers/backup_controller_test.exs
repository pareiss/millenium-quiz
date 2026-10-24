defmodule MillenniumQuizWeb.BackupControllerTest do
  use MillenniumQuizWeb.ConnCase, async: true

  import MillenniumQuiz.QuizFixtures

  test "requires a login", %{conn: conn} do
    conn = get(conn, ~p"/admin/backup.json")
    assert redirected_to(conn) == ~p"/admin/login"
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "sends the backup as a JSON attachment", %{conn: conn} do
      format = format_fixture(%{"name" => "Backup me"})
      conn = get(conn, ~p"/admin/backup.json")

      assert response(conn, 200)
      assert ["application/json" <> _] = get_resp_header(conn, "content-type")
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      [disposition] = get_resp_header(conn, "content-disposition")

      assert disposition =~
               ~r/^attachment; filename="millennium-quiz-backup-\d{4}-\d{2}-\d{2}\.json"$/

      assert %{"version" => 1, "formats" => formats} = Jason.decode!(conn.resp_body)
      assert Enum.any?(formats, &(&1["name"] == format.name))
    end
  end
end
