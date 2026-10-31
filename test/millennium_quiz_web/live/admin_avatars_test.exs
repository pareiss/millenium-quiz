defmodule MillenniumQuizWeb.AdminAvatarsTest do
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{CardSourcesStub, Quiz, Repo}
  alias MillenniumQuiz.Cards.Card

  defp card!(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    Repo.insert!(
      struct!(
        Card,
        Map.merge(
          %{
            name: "Avatar Card #{n}",
            password: n,
            tcg_release_date: ~D[2002-03-08],
            fetched_at: DateTime.utc_now(:second)
          },
          attrs
        )
      )
    )
  end

  test "the page needs a login", %{conn: conn} do
    format = format_fixture()
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/formats/#{format}")
  end

  describe "profile pictures" do
    setup :register_and_log_in_user

    setup do
      %{format: format_fixture(%{"date" => "2005-04-01"})}
    end

    test "shows the count and the chosen cards", %{conn: conn, format: format} do
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format}")
      assert has_element?(view, "#avatar-count", "0 of 40")
      assert has_element?(view, "#avatar-empty")
      assert has_element?(view, "#avatar-cards", "YAML Yugi")

      card = card!(%{name: "Pictured Dragon"})
      {:ok, _} = Quiz.add_avatar_card(format.id, card.id)
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format}")

      assert has_element?(view, "#avatar-count", "1 of 40")
      assert has_element?(view, "#avatar-card-#{card.id}", "Pictured Dragon")

      path = MillenniumQuiz.Avatars.path(MillenniumQuiz.Avatars.card_slug(card.id))
      assert has_element?(view, "#avatar-card-#{card.id} img[src='#{path}']")
      refute has_element?(view, "#avatar-empty")
    end

    test "searches, imports and adds a card, then removes it after asking",
         %{conn: conn, format: format} do
      CardSourcesStub.stub!()
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format}")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)

      # too short: no results; Plain Card (2015) is not released in 2005
      view |> form("#avatar-search", avatar_search: %{query: "re"}) |> render_change()
      refute has_element?(view, "#avatar-results")
      view |> form("#avatar-search", avatar_search: %{query: "card"}) |> render_change()
      refute has_element?(view, "#avatar-results")

      view |> form("#avatar-search", avatar_search: %{query: "reborn"}) |> render_change()
      assert has_element?(view, "#avatar-results", "Monster Reborn")

      view |> element("#add-avatar-83764719") |> render_click()
      render_async(view)

      assert [%{name: "Monster Reborn"} = card] = Quiz.avatar_cards(format.id)
      assert has_element?(view, "#avatar-count", "1 of 40")
      assert has_element?(view, "#avatar-card-#{card.id}")
      refute has_element?(view, "#avatar-results")

      # adding it again changes nothing and starts no import
      render_hook(view, "add_avatar_card", %{"password" => "#{card.password}"})
      assert :sys.get_state(view.pid).socket.assigns.avatar_importing == nil
      assert [_] = Quiz.avatar_cards(format.id)

      view |> element("#remove-avatar-#{card.id}") |> render_click()
      assert has_element?(view, "#remove-avatar-dialog", "Monster Reborn")
      assert [_] = Quiz.avatar_cards(format.id)

      view |> element("#remove-avatar-dialog-cancel") |> render_click()
      refute has_element?(view, "#remove-avatar-dialog")
      assert [_] = Quiz.avatar_cards(format.id)

      view |> element("#remove-avatar-#{card.id}") |> render_click()
      view |> element("#remove-avatar-dialog-confirm") |> render_click()
      assert Quiz.avatar_cards(format.id) == []
      assert has_element?(view, "#avatar-count", "0 of 40")
    end

    test "a failing search shows a message instead of results", %{conn: conn, format: format} do
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format}")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)
      Req.Test.stub(MillenniumQuiz.Cards, &Plug.Conn.send_resp(&1, 500, "down"))

      view |> form("#avatar-search", avatar_search: %{query: "reborn"}) |> render_change()
      assert has_element?(view, "#avatar-search-error")
      refute has_element?(view, "#avatar-results")
    end

    test "says so when the limit is reached", %{conn: conn, format: format} do
      for _ <- 1..Quiz.max_avatar_cards() do
        {:ok, _} = Quiz.add_avatar_card(format.id, card!().id)
      end

      CardSourcesStub.stub!()
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format}")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)
      assert has_element?(view, "#avatar-count", "40 of 40")

      view |> form("#avatar-search", avatar_search: %{query: "reborn"}) |> render_change()
      view |> element("#add-avatar-83764719") |> render_click()
      html = render_async(view)

      assert html =~ "at most 40 profile pictures"
      assert length(Quiz.avatar_cards(format.id)) == 40
      assert has_element?(view, "#avatar-count", "40 of 40")
    end

    test "says so when the card came out after the format's date", %{conn: conn, format: format} do
      CardSourcesStub.stub!()
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format}")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)

      # not offered by the search, but a hand-made client can still ask for it
      render_hook(view, "add_avatar_card", %{"password" => "#{CardSourcesStub.plain().password}"})
      html = render_async(view)

      assert html =~ "was not released yet"
      assert Quiz.avatar_cards(format.id) == []
    end

    test "a failed import shows a message", %{conn: conn, format: format} do
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format}")
      Req.Test.allow(MillenniumQuiz.Cards, self(), view.pid)
      Req.Test.stub(MillenniumQuiz.Cards, &Plug.Conn.send_resp(&1, 500, "down"))

      render_hook(view, "add_avatar_card", %{"password" => "83764719"})
      html = render_async(view)

      assert html =~ ~r/could not be loaded \([^)]+\)/
      assert :sys.get_state(view.pid).socket.assigns.avatar_importing == nil
    end

    test "malformed events are ignored", %{conn: conn, format: format} do
      card = card!()
      {:ok, _} = Quiz.add_avatar_card(format.id, card.id)
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format}")

      for {event, params} <- [
            {"add_avatar_card", %{"password" => "abc"}},
            {"add_avatar_card", %{"password" => 5}},
            {"add_avatar_card", %{}},
            {"remove_avatar_card", %{"id" => "nope"}},
            {"remove_avatar_card", %{}},
            {"remove_avatar_card", %{"id" => "999999999"}},
            {"confirm_delete", %{"what" => "avatar", "id" => "nope"}},
            {"confirm_delete", %{"what" => "avatar", "id" => "999999999"}},
            {"search_avatar_cards", %{}},
            {"search_avatar_cards", %{"avatar_search" => %{"query" => 5}}}
          ] do
        render_hook(view, event, params)
      end

      assert Process.alive?(view.pid)
      refute has_element?(view, "#remove-avatar-dialog")
      assert [%{id: id}] = Quiz.avatar_cards(format.id)
      assert id == card.id
    end
  end
end
