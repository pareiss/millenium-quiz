defmodule MillenniumQuizWeb.DuelThemeTest do
  @moduledoc """
  The opt-in "duel" daisyUI themes: their colour pairs pass WCAG contrast, their
  fonts exist, and the pages still render with the theme script that can select them.
  """
  use MillenniumQuizWeb.ConnCase, async: true

  @css File.read!(Path.expand("../../assets/css/app.css", __DIR__))
  @static Path.expand("../../priv/static", __DIR__)

  # colour pair, minimum ratio: 4.5 for text, 3 for large text and UI parts
  @pairs [
    {"base-content", "base-100", 4.5},
    {"base-content", "base-200", 4.5},
    {"base-content", "base-300", 4.5},
    {"primary", "base-100", 4.5},
    {"primary", "base-200", 4.5},
    {"secondary", "base-100", 4.5},
    {"secondary", "base-200", 4.5},
    {"accent", "base-100", 4.5},
    {"accent", "base-200", 4.5},
    {"primary-content", "primary", 4.5},
    {"secondary-content", "secondary", 4.5},
    {"accent-content", "accent", 4.5},
    {"neutral-content", "neutral", 4.5},
    {"info-content", "info", 4.5},
    {"success-content", "success", 4.5},
    {"warning-content", "warning", 4.5},
    {"error-content", "error", 4.5}
  ]

  defp theme(name) do
    [_, block] = Regex.run(~r/name: "#{name}";(.*?)\n\}/s, @css)

    ~r/--color-([a-z0-9-]+): (#[0-9a-f]{6});/
    |> Regex.scan(block)
    |> Map.new(fn [_, key, hex] -> {key, hex} end)
  end

  defp channel(hex, from) do
    c = hex |> binary_part(from, 2) |> String.to_integer(16) |> Kernel./(255)
    if c <= 0.03928, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
  end

  defp luminance("#" <> _ = hex) do
    hex = String.downcase(hex)
    0.2126 * channel(hex, 1) + 0.7152 * channel(hex, 3) + 0.0722 * channel(hex, 5)
  end

  defp ratio(a, b) do
    {la, lb} = {luminance(a), luminance(b)}
    (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
  end

  for name <- ["duel-dark", "duel-light"], {fg, bg, min} <- @pairs do
    test "#{name}: #{fg} on #{bg} is at least #{min}:1" do
      colors = theme(unquote(name))
      r = ratio(colors[unquote(fg)], colors[unquote(bg)])
      assert r >= unquote(min), "#{unquote(fg)} on #{unquote(bg)}: #{Float.round(r, 2)}:1"
    end
  end

  # `fg` at `alpha` over `bg`, as the browser mixes them (sRGB, which is what
  # color-mix(in oklab) and the /70 utilities approximate closely enough here)
  defp blend(fg, bg, alpha) do
    mixed =
      for from <- [1, 3, 5] do
        f = fg |> binary_part(from, 2) |> String.to_integer(16)
        b = bg |> binary_part(from, 2) |> String.to_integer(16)
        round(f * alpha + b * (1 - alpha))
      end

    "#" <> Enum.map_join(mixed, &(&1 |> Integer.to_string(16) |> String.pad_leading(2, "0")))
  end

  # the text of the player-facing chrome: muted copy (text-base-content/70), the field
  # labels (75%), the format tags and the chosen option cards (primary on a tint of itself)
  for name <- ["duel-dark", "duel-light"] do
    test "#{name}: the muted and tinted text of the chrome is at least 4.5:1" do
      c = theme(unquote(name))

      for bg <- [c["base-100"], c["base-200"]], alpha <- [0.7, 0.75] do
        text = blend(c["base-content"], bg, alpha)
        r = ratio(text, bg)
        assert r >= 4.5, "base-content at #{alpha} on #{bg}: #{Float.round(r, 2)}:1"
      end

      for {fg, tint} <- [{"primary", 0.12}, {"primary", 0.08}, {"base-content", 0.13}] do
        bg = blend(c["primary"], c["base-100"], tint)
        r = ratio(c[fg], bg)
        assert r >= 4.5, "#{fg} on primary tint #{tint}: #{Float.round(r, 2)}:1"
      end

      # the muted description on the chosen option card (13%) and the format hover (7%)
      for tint <- [0.13, 0.07] do
        bg = blend(c["primary"], c["base-100"], tint)
        text = blend(c["base-content"], bg, 0.7)
        r = ratio(text, bg)
        assert r >= 4.5, "base-content at 0.7 on primary tint #{tint}: #{Float.round(r, 2)}:1"
      end

      # the active icon on the primary toggle thumb
      r = ratio(c["primary-content"], c["primary"])
      assert r >= 4.5, "primary-content on primary: #{Float.round(r, 2)}:1"
    end
  end

  test "both themes are defined, they are the default, and the fonts are served" do
    # duel-light is the plain default, duel-dark the one for a dark system
    assert [_, light] = Regex.run(~r/name: "duel-light";(.*?)\n\}/s, @css)
    assert light =~ "default: true;"
    assert light =~ "prefersdark: false;"
    assert [_, dark] = Regex.run(~r/name: "duel-dark";(.*?)\n\}/s, @css)
    assert dark =~ "default: false;"
    assert dark =~ "prefersdark: true;"

    # the old Millennium themes are gone
    refute @css =~ ~s(name: "light";)
    refute @css =~ ~s(name: "dark";)
    refute @css =~ "[data-theme=light]"
    refute @css =~ "[data-theme=dark]"

    for file <- ~w(Orbitron.woff2 Rajdhani-500.woff2 Rajdhani-600.woff2 Rajdhani-700.woff2
                   Orbitron-OFL.txt Rajdhani-OFL.txt) do
      path = Path.join([@static, "fonts", file])
      assert File.exists?(path), "missing #{file}"

      if String.ends_with?(file, ".woff2"),
        do: assert(binary_part(File.read!(path), 0, 4) == "wOF2")
    end

    assert @css =~ "/fonts/Orbitron.woff2"
    assert @css =~ "--duel-cut"
    assert @css =~ "--duel-p4"
  end

  test "the active toggle icon rule is nested with & (same element as the theme attributes)" do
    assert @css =~ "&[data-theme-source=system] .duel-toggle-btn[data-phx-theme=system]"
    refute @css =~ ~r/^\s+\[data-theme-source=system\] \.duel-toggle-btn/m
  end

  test "the light token block does not beat the dark one on <html>" do
    # the theme attribute sits on <html>, which is also :root: a plain :root selector
    # would out-rank [data-theme=duel-dark] by order and paint the dark theme light
    assert @css =~ ":where(:root), [data-theme=duel-light] {"
  end

  describe "the theme script of the root layout" do
    setup %{conn: conn} do
      {:ok, html: conn |> get(~p"/") |> html_response(200)}
    end

    test "the server sets no fixed data-theme, the script does", %{html: html} do
      refute html =~ ~r/<html[^>]*data-theme/
      assert html =~ ~s|root.setAttribute("data-theme", resolve())|
    end

    test "no stored choice and system follow the system's light or dark as duel", %{html: html} do
      assert html =~ ~s|const resolve = () => "duel-" + systemTheme();|
      assert html =~ ~s|system: "duel"|
      assert html =~ ~s|localStorage.getItem("phx:theme")|
      # a live change of the system is followed while the choice is "system"
      assert html =~ "prefers-color-scheme: dark"
      assert html =~ ~s|getAttribute("data-theme-source") === "system"|
    end

    test "stored light and dark (old visitors) become the duel variants", %{html: html} do
      assert html =~ ~s|light: "duel-light"|
      assert html =~ ~s|dark: "duel-dark"|
    end

    test "?theme= keeps working; the old millennium- names are gone", %{html: html} do
      assert html =~ ~s|get("theme")|

      for name <- ~w(system duel duel-light duel-dark) do
        assert html =~ ~s|"#{name}"|
      end

      for old <- ~w(millennium-light millennium-dark), do: refute(html =~ old)
    end

    test "the browser bar colours of the duel themes", %{html: html} do
      assert html =~ ~s|"duel-light": "#eef2f7"|
      assert html =~ ~s|"duel-dark": "#0b0f16"|
    end
  end

  test "the theme toggle offers system, duel light and duel dark" do
    html = Phoenix.LiveViewTest.rendered_to_string(MillenniumQuizWeb.Layouts.theme_toggle(%{}))
    assert html =~ ~s(id="theme-toggle")

    for theme <- ~w(system duel-light duel-dark),
        do: assert(html =~ ~s(data-phx-theme="#{theme}"))

    refute html =~ ~s(data-phx-theme="light")
    refute html =~ ~s(data-phx-theme="dark")
  end

  test "pages render with the theme script and preload the site's fonts", %{conn: conn} do
    for path <- [~p"/", ~p"/?theme=duel", ~p"/?theme=duel-dark", ~p"/?theme=duel-light"] do
      html = conn |> get(path) |> html_response(200)
      assert html =~ ~s("duel-dark")
    end

    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ "/fonts/Orbitron.woff2"
    assert html =~ "/fonts/Rajdhani-500.woff2"
  end

  test "the theme toggle's slider classes are separate tokens" do
    html = Phoenix.LiveViewTest.rendered_to_string(MillenniumQuizWeb.Layouts.theme_toggle(%{}))

    [class] =
      Regex.run(~r/class="([^"]*left-0[^"]*transition-\[left\][^"]*)"/, html,
        capture: :all_but_first
      )

    tokens = String.split(class)

    for t <- [
          "[[data-theme=duel-dark]_&]:left-2/3",
          "[[data-theme-source=system]_&]:!left-0",
          "transition-[left]"
        ],
        do: assert(t in tokens, "missing class token #{t}")

    for t <- ["[[data-theme=light]_&]:left-1/3", "[[data-theme=dark]_&]:left-2/3"],
        do: refute(t in tokens, "class token of a removed theme: #{t}")
  end
end
