defmodule MillenniumQuizWeb.Admin.SessionController do
  use MillenniumQuizWeb, :controller

  alias MillenniumQuiz.Accounts
  alias MillenniumQuizWeb.UserAuth

  def create(conn, %{"user" => %{"username" => username, "password" => password}}) do
    if user = Accounts.get_user_by_username_and_password(username, password) do
      conn
      |> put_flash(:info, "Welcome back, #{user.username}!")
      |> UserAuth.log_in_user(user)
    else
      # Same message for unknown user and wrong password (no user enumeration).
      conn
      |> put_flash(:error, "Invalid username or password")
      |> redirect(to: ~p"/admin/login")
    end
  end

  def update_password(conn, %{"current_password" => current, "user" => user_params}) do
    user = conn.assigns.current_scope.user

    case Accounts.update_user_password(user, current, user_params) do
      {:ok, user} ->
        UserAuth.disconnect_sessions(user)

        conn
        |> put_session(:user_return_to, ~p"/admin/users")
        |> put_flash(:info, "Password updated. Other sessions were logged out.")
        |> UserAuth.log_in_user(user)

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Password could not be updated")
        |> redirect(to: ~p"/admin/users")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
