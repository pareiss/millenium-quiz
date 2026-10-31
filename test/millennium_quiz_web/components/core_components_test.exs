defmodule MillenniumQuizWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import MillenniumQuizWeb.CoreComponents

  test "a table scrolls sideways inside its own wrapper, not the page" do
    assigns = %{rows: [%{name: "Ann"}]}

    html =
      rendered_to_string(~H"""
      <.table id="people" rows={@rows}>
        <:col :let={row} label="Name">{row.name}</:col>
      </.table>
      """)

    doc = LazyHTML.from_fragment(html)

    assert doc
           |> LazyHTML.query("div.overflow-x-auto > table > tbody#people")
           |> Enum.count() == 1
  end

  describe "avatar/1" do
    defp avatar_html(assigns) do
      assigns = Map.new(assigns)

      rendered_to_string(~H"""
      <.avatar {assigns} />
      """)
      |> LazyHTML.from_fragment()
    end

    defp style_of(doc) do
      doc |> LazyHTML.query("span img") |> LazyHTML.attribute("style") |> hd()
    end

    test "a card without a crop gets the default one: 150 percent around the middle" do
      doc = avatar_html(slug: "card-7", title: "Dark Magician", class: "size-14")

      assert style_of(doc) == "width:150.0%;height:150.0%;left:-25.0%;top:-25.0%"

      assert doc |> LazyHTML.query("span img") |> LazyHTML.attribute("src") == [
               "/cards/7/artwork?w=200"
             ]

      assert doc |> LazyHTML.query("span[title='Dark Magician']") |> Enum.count() == 1

      assert doc |> LazyHTML.query("span.overflow-hidden.rounded-full.relative") |> Enum.count() ==
               1

      assert doc |> LazyHTML.query("img.absolute.max-w-none") |> Enum.count() == 1
    end

    test "nil is the default crop" do
      assert style_of(avatar_html(slug: "card-7", crop: nil)) ==
               style_of(avatar_html(slug: "card-7", crop: MillenniumQuiz.Avatars.default_crop()))
    end

    test "the crop's box becomes the inline style" do
      crop = %{x: 40, y: 60, zoom: 200}
      %{size: size, left: left, top: top} = MillenniumQuiz.Avatars.crop_box(crop)
      assert {size, left, top} == {200.0, -30.0, -70.0}

      assert style_of(avatar_html(slug: "card-7", crop: crop)) ==
               "width:200.0%;height:200.0%;left:-30.0%;top:-70.0%"
    end

    test "a focus point near the edge is moved inwards so the image still covers" do
      assert style_of(avatar_html(slug: "card-7", crop: %{x: 0, y: 100, zoom: 300})) ==
               "width:300.0%;height:300.0%;left:0.0%;top:-200.0%"
    end

    test "no zoom shows the whole artwork" do
      assert style_of(avatar_html(slug: "card-7", crop: %{x: 10, y: 90, zoom: 100})) ==
               "width:100.0%;height:100.0%;left:0.0%;top:0.0%"
    end

    test "long fractions are rounded" do
      style = style_of(avatar_html(slug: "card-7", crop: %{x: 33, y: 50, zoom: 170}))
      assert style == "width:170.0%;height:170.0%;left:-6.1%;top:-35.0%"
    end

    test "the sharper artwork is used above a zoom of 150" do
      src = fn zoom ->
        avatar_html(slug: "card-7", crop: %{x: 50, y: 50, zoom: zoom})
        |> LazyHTML.query("img")
        |> LazyHTML.attribute("src")
      end

      assert src.(150) == ["/cards/7/artwork?w=200"]
      assert src.(151) == ["/cards/7/artwork?w=400"]
      assert src.(300) == ["/cards/7/artwork?w=400"]
    end

    test "a monster of the pool is not cropped" do
      doc = avatar_html(slug: "jinzo", crop: %{x: 10, y: 10, zoom: 300})
      assert [img] = LazyHTML.query(doc, "img") |> Enum.to_list()
      assert LazyHTML.attribute(img, "src") == ["/images/avatars/jinzo.jpg"]
      assert LazyHTML.attribute(img, "style") == []
      assert LazyHTML.attribute(img, "class") |> hd() =~ "object-cover"
      assert LazyHTML.query(doc, "span") |> Enum.count() == 0
    end

    test "no slug, an unknown slug and a malformed card slug draw nothing" do
      for slug <- [nil, "unknown", "card-007", "card-"] do
        assert avatar_html(slug: slug) |> LazyHTML.query("img") |> Enum.count() == 0
      end
    end
  end
end
