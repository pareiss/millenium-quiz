defmodule MillenniumQuizWeb.AdminAvatarCropsTest do
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest
  import MillenniumQuiz.QuizFixtures

  alias MillenniumQuiz.{Avatars, Quiz, Repo}
  alias MillenniumQuiz.Cards.Card

  defp card!(name) do
    n = System.unique_integer([:positive])

    Repo.insert!(%Card{
      name: name,
      password: n,
      tcg_release_date: ~D[2002-03-08],
      fetched_at: DateTime.utc_now(:second)
    })
  end

  defp img_style(view, card) do
    view
    |> element("#avatar-card-#{card.id} img")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("style")
    |> hd()
  end

  defp frame_style(view) do
    view
    |> element("#crop-frame")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("style")
    |> hd()
  end

  defp sliders(view, x, y, zoom) do
    view
    |> form("#crop-form", crop: %{x: x, y: y, zoom: zoom})
    |> render_change()
  end

  test "the editor needs a login", %{conn: conn} do
    format = format_fixture()
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/formats/#{format}")
  end

  describe "the crop editor" do
    setup :register_and_log_in_user

    setup %{conn: conn} do
      format = format_fixture(%{"date" => "2005-04-01"})
      a = card!("Crop Dragon")
      b = card!("Other Dragon")
      for card <- [a, b], do: {:ok, _} = Quiz.add_avatar_card(format.id, card.id)
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format}")
      %{format: format, a: a, b: b, view: view}
    end

    test "every card has a crop button that is easy to hit", %{view: view, a: a} do
      assert has_element?(
               view,
               "#crop-avatar-#{a.id}[aria-label='Crop Crop Dragon'].min-h-11.min-w-11"
             )

      refute has_element?(view, "#crop-editor")
    end

    test "opens with the current crop, the artwork, the frame and three previews", %{
      view: view,
      a: a
    } do
      view |> element("#crop-avatar-#{a.id}") |> render_click()

      assert has_element?(view, "#crop-editor", "Crop Dragon")
      assert has_element?(view, "#crop-artwork[phx-hook]")
      assert has_element?(view, "#crop-artwork img[src='/cards/#{a.id}/artwork?w=400']")
      assert has_element?(view, "#crop-x[type=range][min='0'][max='100'][value='50']")
      assert has_element?(view, "#crop-y[type=range][value='50']")
      assert has_element?(view, "#crop-zoom[type=range][min='100'][max='300'][value='150']")
      assert has_element?(view, "label", "Zoom: 150%")
      assert has_element?(view, "#crop-save")
      assert has_element?(view, "#crop-reset")
      assert has_element?(view, "#crop-cancel")

      html = view |> element("#crop-previews") |> render() |> LazyHTML.from_fragment()
      assert LazyHTML.query(html, "span.size-11 img") |> Enum.count() == 1
      assert LazyHTML.query(html, "span.size-14 img") |> Enum.count() == 1
      assert LazyHTML.query(html, "span.size-24 img") |> Enum.count() == 1

      # a frame of 100/zoom of the artwork, in the middle
      assert frame_style(view) =~ "left:16.67%;top:16.67%;width:66.67%;height:66.67%"
    end

    test "the editor opens at the stored crop", %{conn: conn, format: format, a: a} do
      {:ok, _} = Quiz.set_avatar_crop(a.id, %{x: 25, y: 40, zoom: 200})
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format}")
      view |> element("#crop-avatar-#{a.id}") |> render_click()
      assert has_element?(view, "#crop-x[value='25']")
      assert has_element?(view, "#crop-zoom[value='200']")
      assert frame_style(view) =~ "left:0.0%;top:15.0%;width:50.0%;height:50.0%"
    end

    test "the sliders move the frame and the previews", %{view: view, a: a} do
      view |> element("#crop-avatar-#{a.id}") |> render_click()
      sliders(view, "20", "70", "250")

      assert has_element?(view, "label", "Horizontal: 20")
      assert has_element?(view, "label", "Vertical: 70")
      assert has_element?(view, "label", "Zoom: 250%")
      assert frame_style(view) =~ "left:0.0%;top:50.0%;width:40.0%;height:40.0%"

      # the previews are real avatars with this crop (the sharp artwork above 150)
      preview = view |> element("#crop-previews span.size-24 img") |> render()
      assert preview =~ "/cards/#{a.id}/artwork?w=400"
      assert preview =~ "width:250.0%"

      # nothing is saved yet
      assert Quiz.avatar_crop(a.id) == Avatars.default_crop()
      assert img_style(view, a) =~ "width:150.0%"
    end

    test "a click on the artwork (the hook's event) sets the focus point", %{view: view, a: a} do
      view |> element("#crop-avatar-#{a.id}") |> render_click()
      render_hook(view, "crop_focus", %{"x" => 80, "y" => 10})

      assert has_element?(view, "#crop-x[value='80']")
      assert has_element?(view, "#crop-y[value='10']")
      assert has_element?(view, "#crop-zoom[value='150']")
      assert frame_style(view) =~ "left:"
      assert has_element?(view, "label", "Horizontal: 80")
    end

    test "Save stores the crop and the grid shows it", %{view: view, a: a, b: b} do
      view |> element("#crop-avatar-#{a.id}") |> render_click()
      sliders(view, "40", "60", "200")
      html = view |> form("#crop-form") |> render_submit()

      assert Quiz.avatar_crop(a.id) == %{x: 40, y: 60, zoom: 200}
      assert Quiz.avatar_crop(b.id) == Avatars.default_crop()
      assert html =~ "saved"
      refute has_element?(view, "#crop-editor")
      assert img_style(view, a) == "width:200.0%;height:200.0%;left:-30.0%;top:-70.0%"
      assert img_style(view, b) =~ "width:150.0%"
    end

    test "Reset to default deletes the stored crop", %{conn: conn, format: format, a: a} do
      {:ok, _} = Quiz.set_avatar_crop(a.id, %{x: 10, y: 10, zoom: 300})
      {:ok, view, _html} = live(conn, ~p"/admin/formats/#{format}")
      assert img_style(view, a) =~ "width:300.0%"
      view |> element("#crop-avatar-#{a.id}") |> render_click()
      view |> element("#crop-reset") |> render_click()

      assert Quiz.avatar_crop(a.id) == Avatars.default_crop()
      refute Repo.get(MillenniumQuiz.Quiz.CardAvatarCrop, a.id)
      refute has_element?(view, "#crop-editor")
      assert img_style(view, a) =~ "width:150.0%"
    end

    test "Cancel leaves the crop as it was", %{view: view, a: a} do
      view |> element("#crop-avatar-#{a.id}") |> render_click()
      sliders(view, "10", "10", "300")
      view |> element("#crop-cancel") |> render_click()

      refute has_element?(view, "#crop-editor")
      assert Quiz.avatar_crop(a.id) == Avatars.default_crop()
      assert img_style(view, a) =~ "width:150.0%"
    end

    test "one editor is open at a time", %{view: view, a: a, b: b} do
      view |> element("#crop-avatar-#{a.id}") |> render_click()
      sliders(view, "10", "10", "300")
      view |> element("#crop-avatar-#{b.id}") |> render_click()

      assert has_element?(view, "#crop-editor", "Other Dragon")
      refute has_element?(view, "#crop-editor", "Crop Dragon")
      assert has_element?(view, "#crop-x[value='50']")
      assert render(view) |> String.split("id=\"crop-editor\"") |> length() == 2
    end

    test "saving after the card was removed by someone else says so", %{
      view: view,
      format: format,
      a: a
    } do
      view |> element("#crop-avatar-#{a.id}") |> render_click()
      sliders(view, "10", "10", "300")
      :ok = Quiz.remove_avatar_card(format.id, a.id)
      Repo.delete!(a)

      html = view |> form("#crop-form") |> render_submit()
      assert html =~ "doesn&#39;t exist anymore"
      refute has_element?(view, "#crop-editor")
      assert Quiz.avatar_crop(a.id) == Avatars.default_crop()
    end

    test "removing the card being edited closes its editor", %{view: view, a: a} do
      view |> element("#crop-avatar-#{a.id}") |> render_click()
      render_hook(view, "remove_avatar_card", %{"id" => "#{a.id}"})
      refute has_element?(view, "#crop-editor")
    end

    test "a card that is not in this format's list is refused", %{conn: conn, view: view} do
      stranger = card!("Stranger")
      other = format_fixture(%{"name" => "Another format"})
      {:ok, _} = Quiz.add_avatar_card(other.id, stranger.id)
      loose = card!("Not in any list")

      for id <- [stranger.id, loose.id, 999_999_999] do
        render_hook(view, "edit_crop", %{"id" => "#{id}"})
        refute has_element?(view, "#crop-editor")
      end

      # and the editor of a card of the list cannot be pointed at another card
      {:ok, view2, _} = live(conn, ~p"/admin/formats/#{other}")
      render_hook(view2, "edit_crop", %{"id" => "#{stranger.id}"})
      render_hook(view2, "crop_focus", %{"x" => 1, "y" => 2, "id" => "#{loose.id}"})
      view2 |> form("#crop-form") |> render_submit()
      assert Quiz.avatar_crop(loose.id) == Avatars.default_crop()

      assert Quiz.avatar_crop(stranger.id) ==
               Avatars.default_crop() |> Map.put(:x, 1) |> Map.put(:y, 2)
    end

    test "malformed and forged events are ignored", %{view: view, a: a} do
      # without an open editor
      for {event, params} <- [
            {"crop_focus", %{"x" => 1, "y" => 1}},
            {"crop_change", %{"crop" => %{"x" => "1", "y" => "1", "zoom" => "150"}}},
            {"save_crop", %{}},
            {"reset_crop", %{}},
            {"cancel_crop", %{}}
          ] do
        render_hook(view, event, params)
      end

      refute has_element?(view, "#crop-editor")

      for {event, params} <- [
            {"edit_crop", %{}},
            {"edit_crop", %{"id" => "nope"}},
            {"edit_crop", %{"id" => 5.5}}
          ] do
        render_hook(view, event, params)
      end

      refute has_element?(view, "#crop-editor")

      view |> element("#crop-avatar-#{a.id}") |> render_click()

      for {event, params} <- [
            {"crop_focus", %{}},
            {"crop_focus", %{"x" => "5", "y" => "5"}},
            {"crop_focus", %{"x" => 5.5, "y" => 5}},
            {"crop_focus", %{"x" => 101, "y" => 5}},
            {"crop_focus", %{"x" => -1, "y" => 5}},
            {"crop_focus", %{"x" => nil, "y" => 5}},
            {"crop_change", %{}},
            {"crop_change", %{"crop" => "x"}},
            {"crop_change", %{"crop" => %{"x" => "abc", "y" => "1", "zoom" => "150"}}},
            {"crop_change", %{"crop" => %{"x" => "1", "y" => "1", "zoom" => "99"}}},
            {"crop_change", %{"crop" => %{"x" => "1", "y" => "1", "zoom" => "301"}}},
            {"crop_change", %{"crop" => %{"x" => "1", "y" => "1", "zoom" => "150.5"}}},
            {"crop_change", %{"crop" => %{"x" => 1, "y" => 1, "zoom" => 150}}},
            {"crop_change", %{"crop" => %{"x" => "1", "y" => "1"}}}
          ] do
        render_hook(view, event, params)
      end

      assert Process.alive?(view.pid)
      assert has_element?(view, "#crop-editor")
      assert has_element?(view, "#crop-x[value='50']")
      assert has_element?(view, "#crop-y[value='50']")
      assert has_element?(view, "#crop-zoom[value='150']")

      # saving what is left stores nothing (it is the default)
      view |> form("#crop-form") |> render_submit()
      assert Quiz.avatar_crop(a.id) == Avatars.default_crop()
    end
  end
end
