defmodule MillenniumQuizWeb.EndpointTest do
  use MillenniumQuizWeb.ConnCase

  defp put_env_for_test(key, value) do
    old = Application.fetch_env(:millennium_quiz, key)
    Application.put_env(:millennium_quiz, key, value)

    on_exit(fn ->
      case old do
        {:ok, v} -> Application.put_env(:millennium_quiz, key, v)
        :error -> Application.delete_env(:millennium_quiz, key)
      end
    end)
  end

  defp session_cookie(conn) do
    conn
    |> get(~p"/")
    |> Plug.Conn.get_resp_header("set-cookie")
    |> Enum.find(&(&1 =~ "_millennium_quiz_key="))
  end

  test "the session cookie is secure on https deployments only", %{conn: conn} do
    put_env_for_test(:secure_cookies, true)
    cookie = session_cookie(conn)
    assert cookie =~ "secure"
    assert cookie =~ "HttpOnly"
    assert cookie =~ "SameSite=Lax"

    put_env_for_test(:secure_cookies, false)
    refute session_cookie(build_conn()) =~ "secure"
  end

  test "the https redirect is skipped for a deployment served over plain http" do
    put_env_for_test(:force_https, false)
    assert MillenniumQuizWeb.Endpoint.skip_https_redirect?(nil)

    put_env_for_test(:force_https, true)
    refute MillenniumQuizWeb.Endpoint.skip_https_redirect?(nil)
  end

  describe "the force_ssl options of config/prod.exs" do
    # the real options, run through Plug.SSL like the endpoint does
    setup do
      force_ssl =
        "config/prod.exs"
        |> Config.Reader.read!(env: :prod)
        |> get_in([:millennium_quiz, MillenniumQuizWeb.Endpoint, :force_ssl])

      opts =
        MillenniumQuizWeb.Endpoint |> Phoenix.Endpoint.__force_ssl__(force_ssl) |> Plug.SSL.init()

      %{opts: opts}
    end

    defp through_ssl(opts, path, proto, host \\ "quiz.example.com") do
      :get
      |> Plug.Test.conn(path)
      |> Map.put(:host, host)
      |> Plug.Conn.put_req_header("x-forwarded-proto", proto)
      |> Plug.SSL.call(opts)
    end

    test "plain http is redirected to https, https gets HSTS", %{opts: opts} do
      put_env_for_test(:force_https, true)

      conn = through_ssl(opts, "/games/x", "http")
      assert conn.halted
      assert conn.status == 301
      assert [<<"https://", _::binary>>] = Plug.Conn.get_resp_header(conn, "location")

      conn = through_ssl(opts, "/games/x", "https")
      refute conn.halted
      assert [hsts] = Plug.Conn.get_resp_header(conn, "strict-transport-security")
      assert hsts =~ "max-age="
    end

    test "probes and localhost are not redirected", %{opts: opts} do
      put_env_for_test(:force_https, true)

      for path <- ["/healthz/live", "/healthz/ready"] do
        refute through_ssl(opts, path, "http").halted
      end

      refute through_ssl(opts, "/", "http", "localhost").halted
    end

    test "a deployment served over plain http on purpose is not redirected", %{opts: opts} do
      put_env_for_test(:force_https, false)
      refute through_ssl(opts, "/games/x", "http").halted
    end
  end
end
