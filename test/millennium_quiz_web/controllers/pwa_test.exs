defmodule MillenniumQuizWeb.PwaTest do
  use MillenniumQuizWeb.ConnCase, async: true

  defp page(conn), do: conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
  defp attrs(doc, selector, name), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  test "the page links the manifest and the touch icon", %{conn: conn} do
    doc = page(conn)

    assert attrs(doc, "link[rel=manifest]", "href") == ["/manifest.webmanifest"]
    assert attrs(doc, "link[rel=apple-touch-icon]", "href") == ["/images/apple-touch-icon.png"]
  end

  test "the browser bar follows the site's theme, the page extends under the notch", %{conn: conn} do
    doc = page(conn)

    # one meta; the theme script repaints it on every theme change (checked in a browser)
    assert attrs(doc, "meta[name=theme-color]", "content") == ["#fdfaf4"]
    assert attrs(doc, "meta[name=theme-color]", "media") == []

    assert attrs(doc, "meta[name=color-scheme]", "content") == ["light dark"]
    [viewport] = attrs(doc, "meta[name=viewport]", "content")
    assert viewport =~ "viewport-fit=cover"
    assert viewport =~ "interactive-widget=resizes-content"
  end

  test "the card fonts are preloaded as woff2", %{conn: conn} do
    doc = page(conn)

    assert attrs(doc, "link[rel=preload][as=font]", "href") == [
             "/fonts/Cinzel.woff2",
             "/fonts/CrimsonPro.woff2"
           ]

    assert attrs(doc, "link[rel=preload][as=font]", "crossorigin") == ["", ""]
  end

  test "the manifest is served and valid", %{conn: conn} do
    conn = get(conn, ~p"/manifest.webmanifest")
    manifest = conn |> response(200) |> Jason.decode!()

    assert manifest["name"] == "Millennium Quiz"
    assert manifest["display"] == "standalone"
    assert manifest["start_url"] == "/"
    assert manifest["short_name"] && manifest["background_color"] && manifest["theme_color"]
    assert Enum.any?(manifest["icons"], &(&1["purpose"] == "maskable"))
    assert Enum.any?(manifest["icons"], &(&1["sizes"] == "192x192"))
  end

  test "every file the manifest, the layout and the CSS name exists" do
    static = Application.app_dir(:millennium_quiz, "priv/static")
    manifest = static |> Path.join("manifest.webmanifest") |> File.read!() |> Jason.decode!()

    files =
      Enum.map(manifest["icons"], & &1["src"]) ++
        [
          "/images/apple-touch-icon.png",
          "/fonts/Cinzel.woff2",
          "/fonts/CrimsonPro.woff2",
          "/fonts/CrimsonPro-Italic.woff2",
          "/fonts/Orbitron.woff2",
          "/fonts/Rajdhani-500.woff2",
          "/fonts/Rajdhani-600.woff2",
          "/fonts/Rajdhani-700.woff2"
        ]

    for file <- files, do: assert(File.exists?(Path.join(static, file)), "missing #{file}")
  end
end
