defmodule MillenniumQuizWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use MillenniumQuizWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint MillenniumQuizWeb.Endpoint

      use MillenniumQuizWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import MillenniumQuizWeb.ConnCase
    end
  end

  setup tags do
    MillenniumQuiz.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "Setup helper that creates an admin and logs it in."
  def register_and_log_in_user(%{conn: conn}) do
    user = MillenniumQuiz.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  def log_in_user(conn, user) do
    token = MillenniumQuiz.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
