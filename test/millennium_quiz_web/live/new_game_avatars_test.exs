defmodule MillenniumQuizWeb.NewGameAvatarsTest do
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{Avatars, Games, Quiz, Repo}
  alias MillenniumQuiz.Cards.Card

  setup do
    format = playable_format_fixture(1)
    %{format: format, pool: Avatars.pool(Quiz.get_format!(format.id))}
  end

  defp avatars(view), do: :sys.get_state(view.pid).socket.assigns.avatars

  defp card!(name) do
    n = System.unique_integer([:positive])

    Repo.insert!(%Card{
      name: name,
      password: n,
      tcg_release_date: ~D[2002-03-08],
      fetched_at: DateTime.utc_now(:second)
    })
  end

  defp start!(view, names \\ ["Ann", "Bob"]) do
    assert {:error, {:live_redirect, %{to: "/games/" <> id}}} =
             view |> form("#players-form", %{"names" => names}) |> render_submit()

    {:ok, %{game: game}} = Games.fetch_game(id)
    game
  end

  test "every player starts with a different picture of the pool", %{
    conn: conn,
    format: format,
    pool: pool
  } do
    {:ok, view, _} = live(conn, ~p"/formats/#{format.id}/play")
    [a, b] = avatars(view)
    assert a != b
    assert a in pool and b in pool
    assert has_element?(view, "#avatar-button-0[type=button][aria-expanded=false]")
    assert has_element?(view, "#avatar-button-1[aria-label*=\"Player 2's picture\"]")
    refute has_element?(view, "#avatar-panel-0")
  end

  test "the shown pictures are the ones the game gets", %{conn: conn, format: format} do
    {:ok, view, _} = live(conn, ~p"/formats/#{format.id}/play")
    shown = avatars(view)
    game = start!(view)
    assert Enum.map(game.players, & &1.avatar) == shown
  end

  test "choosing a picture opens and closes the panel and is what the game gets", %{
    conn: conn,
    format: format,
    pool: pool
  } do
    {:ok, view, _} = live(conn, ~p"/formats/#{format.id}/play")
    [a, b] = avatars(view)
    wish = Enum.find(pool, &(&1 not in [a, b]))

    view |> element("#avatar-button-0") |> render_click()
    assert has_element?(view, "#avatar-panel-0")
    assert has_element?(view, "#avatar-button-0[aria-expanded=true]")
    assert has_element?(view, "#avatar-choice-0-#{wish}[aria-pressed=false]")
    assert has_element?(view, "#avatar-choice-0-#{a}[aria-pressed=true]")

    # only one panel at a time
    view |> element("#avatar-button-1") |> render_click()
    refute has_element?(view, "#avatar-panel-0")
    assert has_element?(view, "#avatar-panel-1")

    # the same button closes it, and so does Escape
    view |> element("#avatar-button-1") |> render_click()
    refute has_element?(view, "#avatar-panel-1")
    view |> element("#avatar-button-0") |> render_click()
    view |> element("#avatar-panel-0") |> render_keydown(%{"key" => "Escape"})
    refute has_element?(view, "#avatar-panel-0")

    view |> element("#avatar-button-0") |> render_click()
    view |> element("#avatar-choice-0-#{wish}") |> render_click()
    refute has_element?(view, "#avatar-panel-0")
    assert avatars(view) == [wish, b]

    # typing names keeps the choice
    view |> form("#players-form", %{"names" => ["Ann", "Bob"]}) |> render_change()
    assert avatars(view) == [wish, b]

    assert Enum.map(start!(view).players, & &1.avatar) == [wish, b]
  end

  test "a picture of another player is disabled and cannot be taken", %{
    conn: conn,
    format: format
  } do
    {:ok, view, _} = live(conn, ~p"/formats/#{format.id}/play")
    [a, b] = avatars(view)

    view |> element("#avatar-button-0") |> render_click()
    assert has_element?(view, "#avatar-choice-0-#{b}[disabled]")
    refute has_element?(view, "#avatar-choice-0-#{a}[disabled]")

    render_click(view, "pick_avatar", %{"index" => "0", "slug" => b})
    assert avatars(view) == [a, b]
  end

  test "random draws another free picture", %{conn: conn, format: format} do
    {:ok, view, _} = live(conn, ~p"/formats/#{format.id}/play")
    [a, b] = avatars(view)
    view |> element("#avatar-button-0") |> render_click()
    view |> element("#avatar-random-0") |> render_click()
    [a2, b2] = avatars(view)
    assert a2 != a and a2 != b2 and b2 == b
  end

  test "forged events are ignored", %{conn: conn, format: format} do
    {:ok, view, _} = live(conn, ~p"/formats/#{format.id}/play")
    before = avatars(view)

    for params <- [
          %{"index" => "0", "slug" => "not-in-the-pool"},
          %{"index" => "0", "slug" => "card-12345"},
          %{"index" => "7", "slug" => hd(Avatars.default_slugs())},
          %{"index" => "-1", "slug" => hd(Avatars.default_slugs())},
          %{"index" => %{"a" => 1}, "slug" => hd(Avatars.default_slugs())},
          %{"index" => "0", "slug" => %{"a" => 1}},
          %{"index" => "x"}
        ] do
      render_click(view, "pick_avatar", params)
    end

    for event <- ["toggle_avatar", "random_avatar", "remove"],
        params <- [%{"index" => "9"}, %{"index" => %{"a" => 1}}, %{"index" => "abc"}, %{}] do
      render_click(view, event, params)
    end

    assert avatars(view) == before
    refute has_element?(view, "[id^=avatar-panel-]")
    assert has_element?(view, "#player-name-1")
  end

  test "adding and removing players keeps the choices", %{conn: conn, format: format, pool: pool} do
    {:ok, view, _} = live(conn, ~p"/formats/#{format.id}/play")
    [a, b] = avatars(view)
    wish = Enum.find(pool, &(&1 not in [a, b]))
    render_click(view, "pick_avatar", %{"index" => "1", "slug" => wish})

    view |> element("#add-player") |> render_click()
    assert [^a, ^wish, c] = avatars(view)
    assert c not in [a, wish]
    assert has_element?(view, "#avatar-button-2")

    view |> element("#remove-player-0") |> render_click()
    assert [^wish, ^c] = avatars(view)
    refute has_element?(view, "#avatar-button-2")
  end

  test "play again keeps the names and gives every player a picture", %{
    conn: conn,
    format: format,
    pool: pool
  } do
    {:ok, view, _} =
      live(conn, ~p"/formats/#{format.id}/play?players[]=Ann&players[]=Bob&players[]=Cy")

    assert has_element?(view, "#player-name-2[value=Cy]")
    avatars = avatars(view)
    assert length(avatars) == 3
    assert length(Enum.uniq(avatars)) == 3
    assert Enum.all?(avatars, &(&1 in pool))
  end

  test "a format with admin cards offers those, with their names", %{conn: conn} do
    format = playable_format_fixture(1)
    [a, b, c, d] = for n <- ~w(Alpha Beta Gamma Delta), do: card!("#{n} Card")
    for card <- [a, b, c, d], do: {:ok, _} = Quiz.add_avatar_card(format.id, card.id)

    {:ok, view, _} = live(conn, ~p"/formats/#{format.id}/play")
    slugs = Enum.map([a, b, c, d], &Avatars.card_slug(&1.id))
    assert Enum.all?(avatars(view), &(&1 in slugs))

    view |> element("#avatar-button-0") |> render_click()

    for slug <- slugs, do: assert(has_element?(view, "#avatar-choice-0-#{slug}"))
    refute has_element?(view, "#avatar-choice-0-#{hd(Avatars.default_slugs())}")
    assert has_element?(view, "#avatar-button-0[aria-label*=\"Card\"]")

    free = Enum.find(slugs, &(&1 not in tl(avatars(view))))
    view |> element("#avatar-choice-0-#{free}") |> render_click()
    assert hd(avatars(view)) == free
    assert hd(start!(view).players).avatar == free
  end

  test "a format without cards uses its date's set", %{conn: conn} do
    format = format_fixture(%{"date" => "2010-04-24"})
    for topic <- format.topics, do: question_fixture(topic)
    {:ok, view, _} = live(conn, ~p"/formats/#{format.id}/play")
    assert Enum.all?(avatars(view), &(&1 in Avatars.for_format(~D[2010-04-24])))
  end

  test "pictures that left the pool while the page was open are replaced, with a message", %{
    conn: conn
  } do
    format = playable_format_fixture(1)
    cards = for n <- ~w(Alpha Beta Gamma Delta), do: card!("#{n} Card")
    for card <- cards, do: {:ok, _} = Quiz.add_avatar_card(format.id, card.id)
    {:ok, view, _} = live(conn, ~p"/formats/#{format.id}/play")

    # The card that player 1 shows is the one that leaves the list.
    shown = hd(avatars(view))
    gone = Enum.find(cards, &(Avatars.card_slug(&1.id) == shown))
    :ok = Quiz.remove_avatar_card(format.id, gone.id)
    {:ok, _} = Quiz.add_avatar_card(format.id, card!("Epsilon Card").id)
    view |> form("#players-form", %{"names" => ["Ann", "Bob"]}) |> render_submit()

    assert has_element?(view, "#players-error", "pictures")
    assert Enum.all?(avatars(view), &(&1 in Avatars.pool(Quiz.get_format!(format.id))))
  end

  test "the picker and the chosen picture use the crops of the cards", %{conn: conn} do
    format = playable_format_fixture(1)
    cards = for n <- ~w(Alpha Beta Gamma Delta), do: card!("#{n} Card")
    for card <- cards, do: {:ok, _} = Quiz.add_avatar_card(format.id, card.id)
    for card <- cards, do: {:ok, _} = Quiz.set_avatar_crop(card.id, %{x: 40, y: 60, zoom: 200})
    {:ok, view, _} = live(conn, ~p"/formats/#{format.id}/play")

    style = "width:200.0%;height:200.0%;left:-30.0%;top:-70.0%"
    assert has_element?(view, "#avatar-button-0 img[style='#{style}'][src$='?w=400']")

    view |> element("#avatar-button-0") |> render_click()
    [slug | _] = Avatars.pool(Quiz.get_format!(format.id))
    assert has_element?(view, "#avatar-choice-0-#{slug} img[style='#{style}']")
  end
end
