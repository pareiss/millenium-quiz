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
end
