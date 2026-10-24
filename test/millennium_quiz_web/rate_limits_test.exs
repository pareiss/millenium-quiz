defmodule MillenniumQuizWeb.RateLimitsTest do
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.AccountsFixtures
  import MillenniumQuiz.QuizFixtures
  import Swoosh.TestAssertions

  alias MillenniumQuiz.{Games, RateLimit}
  alias MillenniumQuiz.Games.GameRecord

  setup :set_swoosh_global

  setup do
    previous = Application.get_env(:millennium_quiz, RateLimit)
    :ets.delete_all_objects(RateLimit.Backend)

    on_exit(fn ->
      Application.put_env(:millennium_quiz, RateLimit, previous)
      :ets.delete_all_objects(RateLimit.Backend)
    end)
  end

  defp limits(limits),
    do: Application.put_env(:millennium_quiz, RateLimit, enabled: true, limits: limits)

  defp login(conn, username, password \\ "wrong password!", ip \\ {127, 0, 0, 1}) do
    %{conn | remote_ip: ip}
    |> post(~p"/admin/login", user: %{username: username, password: password})
  end

  describe "admin login" do
    test "per address: friendly 429 with Retry-After, also for the right password" do
      limits(login_ip: {2, 60_000})
      user = user_fixture()

      for i <- 1..2 do
        conn = login(build_conn(), "nobody#{i}")
        assert redirected_to(conn) == ~p"/admin/login"
      end

      conn = login(build_conn(), user.username, valid_user_password())
      assert text_response(conn, 429) =~ "Too many login attempts"
      assert [retry_after] = get_resp_header(conn, "retry-after")
      assert String.to_integer(retry_after) in 1..60
      refute get_session(conn, :user_token)

      # another address is not affected
      conn = login(build_conn(), user.username, valid_user_password(), {10, 1, 1, 1})
      assert redirected_to(conn) == ~p"/admin/formats"
    end

    test "per username at an address, ignoring case, whether or not the user exists" do
      limits(login_user: {2, 60_000})
      user = user_fixture()

      for name <- [user.username, "nobody"] do
        for i <- 1..2 do
          conn = login(build_conn(), String.upcase(name), "wrong #{i}", {10, 0, 0, 1})
          assert redirected_to(conn) == ~p"/admin/login"
        end

        conn = login(build_conn(), name, "wrong again", {10, 0, 0, 1})
        assert text_response(conn, 429) =~ "Too many login attempts"
      end
    end

    test "guessing wrong passwords from one address does not lock the admin out elsewhere" do
      limits(login_user: {2, 60_000})
      user = user_fixture()

      for i <- 1..3, do: login(build_conn(), user.username, "wrong #{i}", {10, 0, 0, 1})
      assert text_response(login(build_conn(), user.username, "x", {10, 0, 0, 1}), 429)

      conn = login(build_conn(), user.username, valid_user_password(), {10, 0, 0, 2})
      assert redirected_to(conn) == ~p"/admin/formats"
    end

    test "the normal error message does not depend on the username" do
      limits(login_ip: {10, 60_000})
      user = user_fixture()

      messages =
        for name <- [user.username, "nobody"] do
          conn = login(build_conn(), name)
          Phoenix.Flash.get(conn.assigns.flash, :error)
        end

      assert messages == ["Invalid username or password", "Invalid username or password"]
    end
  end

  describe "password change" do
    setup :register_and_log_in_user

    test "is limited per user", %{conn: conn, user: user} do
      limits(password_user: {2, 60_000})

      params = %{
        "current_password" => "not the password",
        "user" => %{
          "password" => "another password",
          "password_confirmation" => "another password"
        }
      }

      for _ <- 1..2 do
        assert redirected_to(put(conn, ~p"/admin/password", params)) == ~p"/admin/users"
      end

      correct = put_in(params["current_password"], valid_user_password())
      conn = put(conn, ~p"/admin/password", correct)
      assert text_response(conn, 429) =~ "Too many password changes"
      assert [_] = get_resp_header(conn, "retry-after")

      # nothing changed
      assert MillenniumQuiz.Accounts.get_user_by_username_and_password(
               user.username,
               valid_user_password()
             )
    end
  end

  describe "password change in the admin page" do
    setup :register_and_log_in_user

    defp change_password(view, current) do
      view
      |> form("#password-form",
        current_password: current,
        user: %{password: "another password", password_confirmation: "another password"}
      )
      |> render_submit()
    end

    test "is limited per user, sharing the rule with the controller", %{conn: conn, user: user} do
      limits(password_user: {2, 60_000})
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      for _ <- 1..2 do
        assert change_password(view, "not the password") =~ "is not valid"
      end

      # over the limit even the right password is not checked
      change_password(view, valid_user_password())
      assert has_element?(view, "#flash-error", "Too many password changes")
      refute has_element?(view, "#password-form[phx-trigger-action]")

      assert RateLimit.check_rule(:password_user, user.id) != :ok
    end
  end

  describe "global caps" do
    setup do
      %{format: playable_format_fixture(1)}
    end

    test "email_global counts across games and addresses", %{conn: conn, format: format} do
      limits(email_global: {1, 60_000})
      {:ok, one} = Games.create_game(format.id, ["Ann", "Bob"])
      {:ok, two} = Games.create_game(format.id, ["Cy", "Di"])

      view = pause_and_open(conn, one)
      send_to(view, "a@example.com")
      assert_email_sent(to: [{"", "a@example.com"}])

      other = pause_and_open(build_conn(), two)
      assert send_to(other, "b@example.com") =~ "Too many emails"
      refute_email_sent(to: [{"", "b@example.com"}])
    end

    test "create_global counts across addresses", %{format: format} do
      limits(create_global: {1, 60_000})
      before = game_count()

      for ip <- [{10, 0, 0, 1}, {10, 0, 0, 2}] do
        conn = %{build_conn() | remote_ip: ip}
        {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play")
        view |> form("#players-form", %{"names" => ["Ann", "Bob"]}) |> render_submit()
        if ip == {10, 0, 0, 2}, do: assert(has_element?(view, "#players-error", "try again in"))
      end

      assert game_count() == before + 1
    end

    test "there is no global login cap" do
      assert_raise FunctionClauseError, fn -> RateLimit.limit(:login_global) end
    end
  end

  # Number of player inputs on the new game form.
  defp inputs(view),
    do: Enum.count(0..9, &has_element?(view, "#player-name-#{&1}"))

  describe "socket events" do
    test "events over the limit are ignored", %{conn: conn} do
      format = playable_format_fixture(1)
      limits(socket_events: {2, 60_000})
      {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play")

      view |> element("#add-player") |> render_click()
      view |> element("#add-player") |> render_click()
      assert inputs(view) == 4

      # beyond the limit nothing happens
      render_hook(view, "remove", %{"index" => "0"})
      assert inputs(view) == 4
    end

    test "another socket has its own budget", %{conn: conn} do
      format = playable_format_fixture(1)
      limits(socket_events: {1, 60_000})

      for _ <- 1..2 do
        {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play")
        view |> element("#add-player") |> render_click()

        assert inputs(view) == 3
      end
    end
  end

  describe "artwork resizing" do
    import MillenniumQuiz.ArtworkFixtures

    test "over the limit the original is served, cache hits don't count" do
      limits(artwork_resize_ip: {1, 60_000})
      data = jpeg()
      card = card_with_artwork(data)
      ip = {10, 9, 9, 9}

      get_art = fn query ->
        get(%{build_conn() | remote_ip: ip}, "/cards/#{card.id}/artwork#{query}")
      end

      # first miss is resized
      resized = get_art.("?w=200")
      assert [etag] = get_resp_header(resized, "etag")
      assert etag =~ "-200"
      MillenniumQuiz.Cards.ArtworkCache.stats()

      # hit: still resized, not counted
      assert [^etag] = get_resp_header(get_art.("?w=200"), "etag")
      # originals aren't counted either
      assert response(get_art.(""), 200) == data

      # a second miss (other width) is over the limit: the original, with its own ETag
      limited = get_art.("?w=400")
      assert response(limited, 200) == data
      assert [limited_etag] = get_resp_header(limited, "etag")
      refute limited_etag =~ "-400"

      # another client still gets its rendition
      other = get(%{build_conn() | remote_ip: {10, 9, 9, 10}}, "/cards/#{card.id}/artwork?w=400")
      assert [other_etag] = get_resp_header(other, "etag")
      assert other_etag =~ "-400"
    end
  end

  describe "resume email" do
    setup do
      format = playable_format_fixture(1)
      {:ok, id} = Games.create_game(format.id, ["Ann", "Bob"])
      %{id: id, format: format}
    end

    defp pause_and_open(conn, id) do
      {:ok, view, _html} = live(conn, ~p"/games/#{id}")
      view |> element("#pause-game") |> render_click()
      view
    end

    defp send_to(view, address),
      do: view |> form("#email-form", resume: %{email: address}) |> render_submit()

    test "is limited per game", %{conn: conn, id: id} do
      limits(email_game: {2, 60_000})
      view = pause_and_open(conn, id)

      send_to(view, "a@example.com")
      assert_email_sent(to: [{"", "a@example.com"}])
      send_to(view, "b@example.com")
      assert_email_sent(to: [{"", "b@example.com"}])

      html = send_to(view, "c@example.com")
      assert html =~ "Too many emails"
      assert has_element?(view, "#flash-error")
      refute_email_sent(to: [{"", "c@example.com"}])
    end

    test "is limited per address across games", %{conn: conn, id: id, format: format} do
      limits(email_ip: {1, 60_000})
      {:ok, other} = Games.create_game(format.id, ["Cy", "Di"])

      view = pause_and_open(conn, id)
      send_to(view, "a@example.com")
      assert_email_sent(to: [{"", "a@example.com"}])

      other_view = pause_and_open(build_conn(), other)
      assert send_to(other_view, "b@example.com") =~ "Too many emails"
      refute_email_sent(to: [{"", "b@example.com"}])
    end

    test "invalid addresses do not use up the limit", %{conn: conn, id: id} do
      limits(email_game: {1, 60_000})
      view = pause_and_open(conn, id)

      send_to(view, "nope")
      send_to(view, "also nope")
      send_to(view, "a@example.com")
      assert_email_sent(to: [{"", "a@example.com"}])
    end
  end

  describe "new game form input" do
    setup do
      %{format: playable_format_fixture(1)}
    end

    test "a huge or malformed names list is bounded", %{conn: conn, format: format} do
      {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play")

      names = Enum.map(1..100_000, &"p#{&1}") ++ [nil, 5, %{"a" => 1}]
      render_hook(view, "change", %{"names" => [%{"x" => 1}, 7 | names]})
      assert inputs(view) == MillenniumQuiz.Game.max_players()

      long = String.duplicate("x", 5000)
      render_hook(view, "change", %{"names" => [long, "Bob"]})
      assert inputs(view) == 2
      assert has_element?(view, "#player-name-0[value='#{String.duplicate("x", 100)}']")
    end

    test "a name over 24 characters still shows the message on start",
         %{conn: conn, format: format} do
      {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play")

      view
      |> form("#players-form", %{"names" => ["Ann", String.duplicate("y", 60)]})
      |> render_submit()

      assert has_element?(view, "#players-error", "24")
    end
  end

  describe "game creation" do
    setup do
      %{format: playable_format_fixture(1)}
    end

    defp game_count, do: MillenniumQuiz.Repo.aggregate(GameRecord, :count)

    test "is limited per address with a message on the form", %{conn: conn, format: format} do
      limits(create_ip: {1, 60_000})
      before = game_count()

      {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play")
      view |> form("#players-form", %{"names" => ["Ann", "Bob"]}) |> render_submit()
      assert game_count() == before + 1

      {:ok, view, _html} = live(build_conn(), ~p"/formats/#{format.id}/play")
      view |> form("#players-form", %{"names" => ["Ann", "Bob"]}) |> render_submit()
      assert has_element?(view, "#players-error", "try again in")
      assert game_count() == before + 1
    end

    test "the address comes from the socket's connect info", %{conn: conn, format: format} do
      limits(create_ip: {1, 60_000})
      previous = Application.get_env(:millennium_quiz, :trusted_proxy_hops)
      Application.put_env(:millennium_quiz, :trusted_proxy_hops, 1)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:millennium_quiz, :trusted_proxy_hops, previous),
          else: Application.delete_env(:millennium_quiz, :trusted_proxy_hops)
      end)

      start = fn conn, forwarded ->
        # The connected mount reads the connect info, the static render the conn.
        conn =
          conn
          |> put_req_header("x-forwarded-for", forwarded)
          |> put_private(:live_view_connect_info, %{
            peer_data: %{address: {10, 0, 0, 1}, port: 1, ssl_cert: nil},
            x_headers: [{"x-forwarded-for", forwarded}]
          })

        {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play")
        view |> form("#players-form", %{"names" => ["Ann", "Bob"]}) |> render_submit()
        view
      end

      # The spoofed leftmost entry changes nothing; the last one is the client.
      assert_redirect(start.(conn, "1.1.1.1, 9.9.9.9"))
      assert_redirect(start.(build_conn(), "2.2.2.2, 8.8.8.8"))
      view = start.(build_conn(), "3.3.3.3, 9.9.9.9")
      assert has_element?(view, "#players-error", "try again in")
    end

    test "invalid input does not use up the limit", %{conn: conn, format: format} do
      limits(create_ip: {1, 60_000})
      {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play")

      view |> form("#players-form", %{"names" => ["Ann", "ann"]}) |> render_submit()
      assert has_element?(view, "#players-error", "different")
      view |> form("#players-form", %{"names" => ["Ann", "Bob"]}) |> render_submit()
      assert_redirect(view)
    end

    test "names are capped at 24 characters", %{conn: conn, format: format} do
      before = game_count()
      {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play")
      long = String.duplicate("x", 25)
      view |> form("#players-form", %{"names" => ["Ann", long]}) |> render_submit()
      assert has_element?(view, "#players-error", "24")
      assert game_count() == before
    end

    test "malformed events are ignored", %{conn: conn, format: format} do
      {:ok, view, _html} = live(conn, ~p"/formats/#{format.id}/play")
      assert render_hook(view, "start", %{"names" => "Ann"})
      assert render_hook(view, "remove", %{"index" => "x"})
      assert has_element?(view, "#players-form")
    end
  end
end
