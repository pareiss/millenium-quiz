defmodule MillenniumQuizWeb.UserAuth do
  @moduledoc """
  Session handling for admins, following the `phx.gen.auth` structure:
  plugs for controllers and `on_mount` hooks for LiveViews.
  """
  use MillenniumQuizWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias MillenniumQuiz.Accounts
  alias MillenniumQuiz.Accounts.Scope

  @signed_in_path "/admin/categories"

  @doc """
  Logs the user in: renews the session id (prevents fixation attacks),
  stores a fresh session token and redirects.
  """
  def log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, live_socket_id(user))
    |> redirect(to: user_return_to || @signed_in_path)
  end

  @doc "Logs the user out and disconnects their LiveViews."
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      MillenniumQuizWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> redirect(to: ~p"/")
  end

  @doc """
  Disconnects all LiveViews of a user, e.g. after a password change. They
  reconnect and re-authenticate; deleted sessions are redirected to login.
  """
  def disconnect_sessions(user) do
    MillenniumQuizWeb.Endpoint.broadcast(live_socket_id(user), "disconnect", %{})
  end

  defp live_socket_id(user), do: "users_sessions:#{user.id}"

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc "Plug: assigns `current_scope` from the session token."
  def fetch_current_scope_for_user(conn, _opts) do
    user =
      with token when is_binary(token) <- get_session(conn, :user_token),
           {user, _inserted_at} <- Accounts.get_user_by_session_token(token) do
        user
      else
        _ -> nil
      end

    assign(conn, :current_scope, Scope.for_user(user))
  end

  @doc "Plug: sends logged-in users away from the login page."
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns.current_scope do
      conn
      |> redirect(to: @signed_in_path)
      |> halt()
    else
      conn
    end
  end

  @doc "Plug: requires a logged-in admin."
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_scope do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/admin/login")
      |> halt()
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  @doc """
  LiveView `on_mount` hooks:

    * `:mount_current_scope` - assigns `current_scope` (may be nil)
    * `:require_authenticated` - halts and redirects to login without a user
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/admin/login")

      {:halt, socket}
    end
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      with token when is_binary(token) <- session["user_token"],
           {user, _inserted_at} <- Accounts.get_user_by_session_token(token) do
        Scope.for_user(user)
      else
        _ -> nil
      end
    end)
  end
end
