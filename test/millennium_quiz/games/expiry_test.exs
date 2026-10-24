defmodule MillenniumQuiz.Games.ExpiryTest do
  use MillenniumQuiz.DataCase

  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.Games
  alias MillenniumQuiz.Games.{Expiry, GameRecord}

  test "runs on a timer and deletes expired games" do
    format = playable_format_fixture(1)
    {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])

    old = DateTime.utc_now() |> DateTime.add(-400 * 86_400, :second) |> DateTime.truncate(:second)
    Repo.update_all(from(g in GameRecord, where: g.id == ^id), set: [updated_at: old])

    # The job is not part of the supervision tree in test (no :game_expiry_days).
    pid = start_supervised!({Expiry, first_run: 3_600_000, interval: 3_600_000})
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    send(pid, :run)
    _ = :sys.get_state(pid)

    refute Repo.exists?(from g in GameRecord, where: g.id == ^id)
  end
end
