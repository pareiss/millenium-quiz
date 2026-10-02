defmodule MillenniumQuiz.AccountsFixtures do
  def valid_user_password, do: "hello world password"
  def unique_username, do: "admin#{System.unique_integer([:positive])}"

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{username: unique_username(), password: valid_user_password()})
      |> MillenniumQuiz.Accounts.register_user()

    user
  end
end
