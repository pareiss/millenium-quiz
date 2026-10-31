defmodule MillenniumQuizWeb.GameAvatarCropsTest do
  # Not async: the game servers are other processes that share the connection.
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{Avatars, Games, Quiz, Repo}
  alias MillenniumQuiz.Cards.Card

  @names ["Ann", "Bob", "Cy", "Di"]

  setup do
    format = playable_format_fixture(1)

    cards =
      for _ <- 1..4 do
        n = System.unique_integer([:positive])

        Repo.insert!(%Card{
          name: "Pic #{n}",
          password: n,
          tcg_release_date: ~D[2002-03-08],
          fetched_at: DateTime.utc_now(:second)
        })
      end

    for card <- cards, do: {:ok, _} = Quiz.add_avatar_card(format.id, card.id)
    slugs = Enum.map(cards, &Avatars.card_slug(&1.id))
    {:ok, id} = Games.create_game(format.id, @names, avatars: slugs, mode: :free)
    %{id: id, cards: cards, slugs: slugs, format: format}
  end

  defp style_of(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("style")
    |> hd()
  end

  test "the stored crop of a card is used on the game page", %{conn: conn, id: id, cards: cards} do
    [first | rest] = cards
    {:ok, _} = Quiz.set_avatar_crop(first.id, %{x: 40, y: 60, zoom: 200})

    {:ok, view, html} = live(conn, ~p"/games/#{id}")

    assert style_of(view, "#scoreboard #score-0 img") ==
             "width:200.0%;height:200.0%;left:-30.0%;top:-70.0%"

    assert html =~ "/cards/#{first.id}/artwork?w=400"

    # the others have the default
    for {card, i} <- Enum.with_index(rest, 1) do
      assert style_of(view, "#scoreboard #score-#{i} img") ==
               "width:150.0%;height:150.0%;left:-25.0%;top:-25.0%"

      assert has_element?(view, "#score-#{i} img[src='/cards/#{card.id}/artwork?w=200']")
    end
  end

  test "the player's crop is used in the pass-the-device bar too", %{
    conn: conn,
    id: id,
    cards: cards
  } do
    for card <- cards, do: {:ok, _} = Quiz.set_avatar_crop(card.id, %{x: 0, y: 0, zoom: 300})
    {:ok, view, _html} = live(conn, ~p"/games/#{id}")

    view |> element("#question-0") |> render_click()
    assert has_element?(view, "#current-player")

    assert style_of(view, "[data-turn-panel] .mq-passbar img") ==
             "width:300.0%;height:300.0%;left:0.0%;top:0.0%"
  end

  test "an update of the game does not ask the database for the crops again", %{
    conn: conn,
    id: id
  } do
    {:ok, view, _html} = live(conn, ~p"/games/#{id}")
    {:ok, fresh} = Games.fetch_game(id)
    me = view.pid
    test_pid = self()
    handler = "crops-queries-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:millennium_quiz, :repo, :query],
      fn _event, _measure, meta, _config ->
        if self() in [me, test_pid], do: send(test_pid, {:query, self() == me, meta.query})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    # the probe works: a query of this very process would be seen
    Repo.query!("select 1")
    send(test_pid, :probe)

    send(view.pid, {:game_updated, fresh})
    render(view)
    assert_received {:query, false, _}
    refute_received {:query, true, _}
  end
end
