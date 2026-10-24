defmodule MillenniumQuizWeb.Admin.SessionController do
  use MillenniumQuizWeb, :controller

  alias MillenniumQuiz.Accounts
  alias MillenniumQuiz.RateLimit
  alias MillenniumQuizWeb.{ClientIP, UserAuth}

  def create(conn, %{"user" => %{"username" => username, "password" => password}})
      when is_binary(username) and is_binary(password) do
    # Counted per address and per (lowercased) username whether or not the user
    # exists, so the limit says nothing about which usernames are real.
    limits = [
      login_ip: ClientIP.from_conn(conn),
      login_user: username |> String.trim() |> String.downcase() |> String.slice(0, 100)
    ]

    with :ok <- RateLimit.check_all(limits),
         user when not is_nil(user) <-
           Accounts.get_user_by_username_and_password(username, password) do
      conn
      |> put_flash(:info, "Welcome back, #{user.username}!")
      |> UserAuth.log_in_user(user)
    else
      {:error, retry_after_ms} ->
        too_many_requests(conn, "Too many login attempts.", retry_after_ms)

      nil ->
        # Same message for unknown user and wrong password (no user enumeration).
        conn
        |> put_flash(:error, "Invalid username or password")
        |> redirect(to: ~p"/admin/login")
    end
  end

  def update_password(conn, %{"current_password" => current, "user" => user_params}) do
    user = conn.assigns.current_scope.user

    case RateLimit.check_rule(:password_user, user.id) do
      :ok -> do_update_password(conn, user, current, user_params)
      {:error, ms} -> too_many_requests(conn, "Too many password changes.", ms)
    end
  end

  defp too_many_requests(conn, what, retry_after_ms) do
    conn
    |> put_resp_header("retry-after", to_string(RateLimit.retry_after_seconds(retry_after_ms)))
    |> put_resp_content_type("text/plain")
    |> send_resp(429, "#{what} Please try again in #{RateLimit.describe_wait(retry_after_ms)}.")
  end

  defp do_update_password(conn, user, current, user_params) do
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
