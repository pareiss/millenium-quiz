defmodule MillenniumQuizWeb.ClientIP do
  @moduledoc """
  The client address of a request, as a string, for rate limiting.

  Behind a reverse proxy the connection's own address is the proxy's.
  `config :millennium_quiz, :trusted_proxy_hops, n` says how many proxies of
  ours sit in front of the app. With `n > 0` the address is the n-th entry
  from the right of `X-Forwarded-For` (every proxy appends the address it
  received the request from, so the entries on the left are client-controlled
  and never used). With `0` the header is ignored.

  A missing or unparsable entry falls back to the connection's address.

  The identity is an IPv4 address (also when IPv4-mapped in IPv6), or for IPv6
  the /64 network like `2001:db8:1:2::/64`: one customer usually owns a whole
  /64, so counting full addresses would let them rotate through billions.
  """

  @doc "Client address of a `Plug.Conn`."
  def from_conn(%Plug.Conn{} = conn) do
    headers = Plug.Conn.get_req_header(conn, "x-forwarded-for")
    resolve(conn.remote_ip, headers, hops())
  end

  @doc """
  Client address of a LiveView socket. Only valid during `mount/3`, and needs
  `:peer_data` and `:x_headers` in the socket's `connect_info`.
  """
  def from_socket(socket) do
    remote =
      case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
        %{address: address} -> address
        _ -> nil
      end

    headers =
      case Phoenix.LiveView.get_connect_info(socket, :x_headers) do
        list when is_list(list) -> for {"x-forwarded-for", value} <- list, do: value
        _ -> []
      end

    resolve(remote, headers, hops())
  end

  @doc """
  Pure resolution: `remote` is an address tuple (or nil), `forwarded_for` the
  list of `X-Forwarded-For` header values, `hops` the trusted proxy count.
  """
  def resolve(remote, forwarded_for, hops) when is_integer(hops) and hops > 0 do
    entries =
      forwarded_for
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&String.trim/1)

    with true <- length(entries) >= hops,
         entry = Enum.at(entries, -hops),
         {:ok, address} <- :inet.parse_address(String.to_charlist(entry)) do
      format(address)
    else
      _ -> format(remote)
    end
  end

  def resolve(remote, _forwarded_for, _hops), do: format(remote)

  @doc """
  Normalised rate-limit identity of an address tuple: IPv4 as is, IPv6 as its
  /64 network; `"unknown"` for anything else.
  """
  def format({0, 0, 0, 0, 0, 0xFFFF, a, b}),
    do: format({div(a, 256), rem(a, 256), div(b, 256), rem(b, 256)})

  def format({a, b, c, d, _, _, _, _} = address) when tuple_size(address) == 8 do
    network = {a, b, c, d, 0, 0, 0, 0}
    "#{network |> :inet.ntoa() |> to_string() |> String.downcase()}/64"
  rescue
    _ -> "unknown"
  end

  def format(address) when tuple_size(address) == 4 do
    address |> :inet.ntoa() |> to_string()
  rescue
    _ -> "unknown"
  end

  def format(_), do: "unknown"

  defp hops do
    case Application.get_env(:millennium_quiz, :trusted_proxy_hops, 0) do
      n when is_integer(n) and n > 0 -> n
      _ -> 0
    end
  end
end
