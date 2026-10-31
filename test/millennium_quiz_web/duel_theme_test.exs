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

  test "both themes are defined, not the default, and the fonts are served" do
    for name <- ["duel-dark", "duel-light"] do
      assert [_, block] = Regex.run(~r/name: "#{name}";(.*?)\n\}/s, @css)
      assert block =~ "default: false;"
      assert block =~ "prefersdark: false;"
    end

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

  test "pages render with the theme script and still default to the old themes", %{conn: conn} do
    for path <- [~p"/", ~p"/?theme=duel", ~p"/?theme=duel-dark", ~p"/?theme=duel-light"] do
      html = conn |> get(path) |> html_response(200)
      assert html =~ ~s("duel-dark")
    end

    # the duel fonts are not preloaded: nothing changes unless the theme is chosen
    html = conn |> get(~p"/") |> html_response(200)
    refute html =~ "Orbitron"
    refute html =~ "Rajdhani"
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
  end
end
