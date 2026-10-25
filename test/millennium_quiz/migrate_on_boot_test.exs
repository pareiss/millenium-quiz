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

  describe "the first admin" do
    alias MillenniumQuiz.Accounts.User

    setup do
      Repo.delete_all(User)
      System.put_env("ADMIN_USERNAME", "bootadmin")
      System.put_env("ADMIN_PASSWORD", "a long boot password 1")

      on_exit(fn ->
        System.delete_env("ADMIN_USERNAME")
        System.delete_env("ADMIN_PASSWORD")
      end)
    end

    test "is created from ADMIN_* when there is no user yet" do
      assert MigrateOnBoot.run(Repo, true) == :ok

      assert [%User{username: "bootadmin"}] = Repo.all(User)

      assert MillenniumQuiz.Accounts.get_user_by_username_and_password(
               "bootadmin",
               "a long boot password 1"
             )
    end

    test "is not created when a user exists" do
      {:ok, _} =
        MillenniumQuiz.Accounts.register_user(%{
          username: "existing",
          password: "another long password"
        })

      assert MigrateOnBoot.run(Repo, true) == :ok
      assert [%User{username: "existing"}] = Repo.all(User)
    end

    test "is not created without the password" do
      System.delete_env("ADMIN_PASSWORD")
      assert MigrateOnBoot.run(Repo, true) == :ok
      assert Repo.all(User) == []
    end

    test "an existing password is only reset with ADMIN_PASSWORD_RESET=true" do
      {:ok, user} =
        MillenniumQuiz.Accounts.register_user(%{
          username: "bootadmin",
          password: "the old long password"
        })

      token = MillenniumQuiz.Accounts.generate_user_session_token(user)

      assert MigrateOnBoot.run(Repo, true) == :ok

      refute MillenniumQuiz.Accounts.get_user_by_username_and_password(
               "bootadmin",
               "a long boot password 1"
             )

      System.put_env("ADMIN_PASSWORD_RESET", "true")
      on_exit(fn -> System.delete_env("ADMIN_PASSWORD_RESET") end)

      assert MigrateOnBoot.run(Repo, true) == :ok

      assert MillenniumQuiz.Accounts.get_user_by_username_and_password(
               "bootadmin",
               "a long boot password 1"
             )

      refute MillenniumQuiz.Accounts.get_user_by_username_and_password(
               "bootadmin",
               "the old long password"
             )

      refute MillenniumQuiz.Accounts.get_user_by_session_token(token)
    end

    test "the reset finds the user whatever the case or spaces of ADMIN_USERNAME" do
      {:ok, _} =
        MillenniumQuiz.Accounts.register_user(%{
          username: "bootadmin",
          password: "the old long password"
        })

      System.put_env("ADMIN_USERNAME", "  BootAdmin ")
      System.put_env("ADMIN_PASSWORD_RESET", "true")
      on_exit(fn -> System.delete_env("ADMIN_PASSWORD_RESET") end)

      assert MigrateOnBoot.run(Repo, true) == :ok

      assert MillenniumQuiz.Accounts.get_user_by_username_and_password(
               "bootadmin",
               "a long boot password 1"
             )
    end

    test "the reset leaves the sessions alone when the password already matches" do
      {:ok, user} =
        MillenniumQuiz.Accounts.register_user(%{
          username: "bootadmin",
          password: "a long boot password 1"
        })

      token = MillenniumQuiz.Accounts.generate_user_session_token(user)

      System.put_env("ADMIN_PASSWORD_RESET", "true")
      on_exit(fn -> System.delete_env("ADMIN_PASSWORD_RESET") end)

      assert MigrateOnBoot.run(Repo, true) == :ok
      assert MillenniumQuiz.Accounts.get_user_by_session_token(token)
    end

    test "running twice creates it once" do
      assert MigrateOnBoot.run(Repo, true) == :ok
      assert MigrateOnBoot.run(Repo, true) == :ok
      assert Repo.aggregate(User, :count) == 1
    end
  end
end
