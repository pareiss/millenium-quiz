defmodule MillenniumQuizWeb.Admin.BackupController do
  @moduledoc "Downloads the quiz backup (see `MillenniumQuiz.Quiz.Export`). Admin only."
  use MillenniumQuizWeb, :controller

  alias MillenniumQuiz.Quiz.Export

  def show(conn, _params) do
    filename = "millennium-quiz-backup-#{Date.utc_today()}.json"

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, Export.to_json())
  end
end
