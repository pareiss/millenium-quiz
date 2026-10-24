defmodule MillenniumQuiz.MigrateOnBootTest do
  use MillenniumQuiz.DataCase

  alias MillenniumQuiz.MigrateOnBoot

  test "is a no-op when disabled" do
    assert MigrateOnBoot.run(Repo, false) == :noop
    assert MigrateOnBoot.run(Repo, nil) == :noop
  end

  test "is disabled by default in the test environment" do
    assert Application.get_env(:millennium_quiz, :migrate_on_boot, false) == false
    assert MigrateOnBoot.start_link([]) == :ignore
  end

  test "enabled: migrates the running repo (nothing pending) and keeps it running" do
    repo_pid = Process.whereis(Repo)
    assert MigrateOnBoot.run(Repo, true) == :ok
    assert Process.whereis(Repo) == repo_pid
    assert Repo.query!("SELECT 1").rows == [[1]]
  end

  test "enabled: a failing migration raises with a clear message" do
    defmodule BrokenRepo do
      def config, do: raise("no database")
    end

    assert_raise RuntimeError, ~r/Migration on boot failed/, fn ->
      MigrateOnBoot.run(BrokenRepo, true)
    end
  end
end
