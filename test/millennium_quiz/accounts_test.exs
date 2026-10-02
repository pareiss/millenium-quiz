defmodule MillenniumQuiz.AccountsTest do
  use MillenniumQuiz.DataCase, async: true

  import MillenniumQuiz.AccountsFixtures

  alias MillenniumQuiz.Accounts
  alias MillenniumQuiz.Accounts.UserToken

  test "passwords are hashed with bcrypt and never stored in plain text" do
    user = user_fixture()
    assert "$2b$" <> _ = user.hashed_password
    assert is_nil(user.password)
  end

  test "register_user/1 validates username and password" do
    assert {:error, cs} = Accounts.register_user(%{username: "Bad Name!", password: "short"})
    assert %{username: [_], password: ["should be at least 12 character(s)"]} = errors_on(cs)

    user_fixture(%{username: "kaiba"})

    assert {:error, cs} =
             Accounts.register_user(%{username: "KAIBA", password: valid_user_password()})

    assert %{username: ["has already been taken"]} = errors_on(cs)
  end

  test "get_user_by_username_and_password/2" do
    user = user_fixture(%{username: "yugi"})

    assert Accounts.get_user_by_username_and_password(" Yugi ", valid_user_password()).id ==
             user.id

    refute Accounts.get_user_by_username_and_password("yugi", "wrong password!!")
    refute Accounts.get_user_by_username_and_password("nobody", valid_user_password())
  end

  test "session tokens are stored hashed and can be revoked" do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)

    refute Repo.get_by(UserToken, token: token)
    assert {%{id: id}, _} = Accounts.get_user_by_session_token(token)
    assert id == user.id

    Accounts.delete_user_session_token(token)
    refute Accounts.get_user_by_session_token(token)
  end

  test "update_user_password/3 checks the current password and expires sessions" do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)
    attrs = %{password: "new valid password", password_confirmation: "new valid password"}

    assert {:error, cs} = Accounts.update_user_password(user, "wrong", attrs)
    assert %{current_password: ["is not valid"]} = errors_on(cs)

    assert {:ok, _} = Accounts.update_user_password(user, valid_user_password(), attrs)
    refute Accounts.get_user_by_session_token(token)
    assert Accounts.get_user_by_username_and_password(user.username, "new valid password")
  end
end
