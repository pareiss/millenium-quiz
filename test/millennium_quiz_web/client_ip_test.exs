defmodule MillenniumQuizWeb.ClientIPTest do
  use ExUnit.Case

  alias MillenniumQuizWeb.ClientIP

  @remote {10, 0, 0, 7}

  describe "resolve/3" do
    test "without trusted proxies the header is ignored" do
      assert ClientIP.resolve(@remote, ["1.2.3.4"], 0) == "10.0.0.7"
    end

    test "takes the n-th entry from the right" do
      header = ["9.9.9.9, 1.1.1.1, 2.2.2.2"]
      assert ClientIP.resolve(@remote, header, 1) == "2.2.2.2"
      assert ClientIP.resolve(@remote, header, 2) == "1.1.1.1"
    end

    test "a spoofed leftmost entry never wins" do
      # The client sent "6.6.6.6"; our proxy appended the real address.
      assert ClientIP.resolve(@remote, ["6.6.6.6, 203.0.113.5"], 1) == "203.0.113.5"
    end

    test "several header lines count as one list" do
      assert ClientIP.resolve(@remote, ["6.6.6.6", "203.0.113.5"], 1) == "203.0.113.5"
    end

    test "missing, short or garbled headers fall back to the connection" do
      assert ClientIP.resolve(@remote, [], 1) == "10.0.0.7"
      assert ClientIP.resolve(@remote, ["1.2.3.4"], 2) == "10.0.0.7"
      assert ClientIP.resolve(@remote, ["not an ip"], 1) == "10.0.0.7"
      assert ClientIP.resolve(@remote, ["1.2.3.4, , "], 1) == "10.0.0.7"
      assert ClientIP.resolve(@remote, ["1.2.3.4:80"], 1) == "10.0.0.7"
    end

    test "unknown when nothing is known" do
      assert ClientIP.resolve(nil, [], 0) == "unknown"
      assert ClientIP.resolve(nil, ["junk"], 1) == "unknown"
    end

    test "IPv6 is normalised" do
      assert ClientIP.resolve(nil, ["2001:DB8:0:0:0:0:0:1"], 1) == "2001:db8::1"
      assert ClientIP.resolve({0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}, [], 0) == "2001:db8::1"
      assert ClientIP.resolve(nil, ["::ffff:1.2.3.4"], 1) == "1.2.3.4"
      assert ClientIP.resolve({0, 0, 0, 0, 0, 0xFFFF, 0x0102, 0x0304}, [], 0) == "1.2.3.4"
    end
  end

  describe "from_conn/1" do
    setup do
      previous = Application.get_env(:millennium_quiz, :trusted_proxy_hops)

      on_exit(fn ->
        case previous do
          nil -> Application.delete_env(:millennium_quiz, :trusted_proxy_hops)
          value -> Application.put_env(:millennium_quiz, :trusted_proxy_hops, value)
        end
      end)
    end

    defp conn_with(header) do
      conn = %{Plug.Test.conn(:get, "/") | remote_ip: @remote}
      if header, do: Plug.Conn.put_req_header(conn, "x-forwarded-for", header), else: conn
    end

    test "reads the configured hop count" do
      Application.delete_env(:millennium_quiz, :trusted_proxy_hops)
      assert ClientIP.from_conn(conn_with("6.6.6.6, 5.5.5.5")) == "10.0.0.7"

      Application.put_env(:millennium_quiz, :trusted_proxy_hops, 1)
      assert ClientIP.from_conn(conn_with("6.6.6.6, 5.5.5.5")) == "5.5.5.5"
      assert ClientIP.from_conn(conn_with(nil)) == "10.0.0.7"
    end

    test "a nonsensical hop count means no trusted proxy" do
      Application.put_env(:millennium_quiz, :trusted_proxy_hops, "1")
      assert ClientIP.from_conn(conn_with("5.5.5.5")) == "10.0.0.7"
    end
  end
end
