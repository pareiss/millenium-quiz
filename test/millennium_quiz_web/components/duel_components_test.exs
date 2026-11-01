defmodule MillenniumQuizWeb.DuelComponentsTest do
  use MillenniumQuizWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import MillenniumQuizWeb.DuelComponents

  @css File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

  defp parse(html), do: LazyHTML.from_fragment(html)
  defp text(html, selector), do: html |> parse() |> LazyHTML.query(selector) |> LazyHTML.text()
  defp count(html, selector), do: html |> parse() |> LazyHTML.query(selector) |> Enum.count()

  defp attr(html, selector, name),
    do: html |> parse() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp gauge(overrides \\ []) do
    assigns =
      Enum.into(overrides, %{
        name: "Yugi",
        avatar: "elemental-hero-stratos",
        lp: 4000,
        start_lp: 4000
      })

    render_component(&lp_gauge/1, assigns)
  end

  describe "lp_gauge" do
    test "shows the LP with leading zeros as real text, in one markup for every size" do
      html = gauge(lp: 4000)
      assert text(html, ".duel-gauge-num") == "04000"
      assert text(html, ".duel-gauge-name") == "Yugi"
      assert count(html, ".duel-gauge-avatar") == 1
      assert count(html, ".duel-gauge-plate") == 1
      assert count(html, ".duel-gauge-bar") == 1
      assert attr(html, ".duel-gauge-bar", "role") == ["progressbar"]
      assert attr(html, ".duel-gauge-bar", "aria-label") == ["Yugi's life points"]
      assert attr(html, ".duel-gauge-bar", "aria-valuenow") == ["4000"]
      assert attr(html, ".duel-gauge-bar", "aria-valuemax") == ["4000"]
      assert attr(html, ".duel-gauge-fill", "style") == ["width:100.0%"]

      assert text(gauge(lp: 30), ".duel-gauge-num") == "00030"
      assert text(gauge(lp: 8000, start_lp: 8000), ".duel-gauge-num") == "08000"
      assert text(gauge(lp: 12_000, start_lp: 12_000), ".duel-gauge-num") == "12000"
      assert text(gauge(lp: 5, start_lp: 100_000), ".duel-gauge-num") == "000005"
    end

    test "the number and the bar take the ids the game screens give them" do
      html = gauge(lp_id: "lp-0", bar_id: "lp-bar-0", lp: 1000)
      assert text(html, "#lp-0") == "01000"
      assert attr(html, "#lp-0", "data-lp") == ["1000"]
      assert attr(html, "#lp-0", "phx-hook") == ["MillenniumQuizWeb.DuelComponents.LpCount"]
      # no id, no hook (a hook needs one)
      assert attr(gauge(), ".duel-gauge-num", "phx-hook") == []
      assert attr(html, "#lp-bar-0", "aria-valuenow") == ["1000"]
      assert attr(html, "#lp-bar-0 .duel-gauge-fill", "style") == ["width:25.0%"]
    end

    test "the size classes are container queries in the CSS, on a size container" do
      assert gauge() =~ "duel-gauge"
      assert @css =~ "container-type: inline-size"

      for max <- ["419.98px", "299.98px", "99.98px"],
          do: assert(@css =~ "@container duel-gauge (max-width: #{max})")
    end

    test "the bar depletes with the LP, a living player keeps a sliver" do
      assert attr(gauge(lp: 1000), ".duel-gauge-fill", "style") == ["width:25.0%"]
      assert attr(gauge(lp: 10), ".duel-gauge-fill", "style") == ["width:3.0%"]
    end

    test "the player index picks the colour and is clamped" do
      assert attr(gauge(player: 2), ".duel-gauge", "data-player") == ["3"]
      assert attr(gauge(player: 9), ".duel-gauge", "data-player") == ["4"]
      assert attr(gauge(player: -1), ".duel-gauge", "data-player") == ["1"]
    end

    test "a hit shows the damage as text and a ghost segment after the fill" do
      html = gauge(lp: 3000, status: :hit, damage: 500)
      assert attr(html, ".duel-gauge", "data-status") == ["hit"]
      assert text(html, ".duel-gauge-dmg") =~ "−500"
      assert attr(html, ".duel-gauge-ghost", "style") == ["left:75.0%;width:12.5%"]
      # no ghost beyond the end of the bar
      assert attr(gauge(lp: 3000, damage: 9000), ".duel-gauge-ghost", "style") ==
               ["left:75.0%;width:25.0%"]

      assert text(gauge(status: :hit), ".duel-gauge-dmg") =~ "HIT"
      # no damage text without a hit, and none for zero damage
      assert count(gauge(lp: 3000, damage: 500), ".duel-gauge-dmg") == 0
      assert count(gauge(lp: 3000, status: :hit, damage: 0), ".duel-gauge-ghost") == 0
      refute text(gauge(lp: 3000, status: :hit, damage: 0), ".duel-gauge-dmg") =~ "−0"
      assert count(gauge(), ".duel-gauge-ghost") == 0
    end

    test "an eliminated player shows K.O. as text, a grey empty bar" do
      html = gauge(lp: 0, status: :eliminated)
      assert text(html, ".duel-gauge-ko") =~ "K.O."
      assert text(html, ".duel-gauge-num") == "00000"
      assert attr(html, ".duel-gauge-fill", "style") == ["width:0.0%"]
      assert attr(html, ".duel-gauge", "data-status") == ["eliminated"]
      # 0 LP is K.O. even if the caller forgot the status, or passed :hit for
      # the very hit that knocked the player out (the ghost still shows it)
      assert text(gauge(lp: 0), ".duel-gauge-ko") =~ "K.O."
      knocked_out = gauge(lp: 0, status: :hit, damage: 500)
      assert text(knocked_out, ".duel-gauge-ko") =~ "K.O."
      assert attr(knocked_out, ".duel-gauge", "data-status") == ["eliminated"]
      assert count(knocked_out, ".duel-gauge-ghost") == 1
      assert count(gauge(), ".duel-gauge-ko") == 0
    end

    test "the active player is marked for assistive technology and has a Synchro ring" do
      active = gauge(active: true)
      assert attr(active, ".duel-gauge-body", "aria-current") == ["true"]
      assert count(active, "svg use[href='#duel-ring']") == 1

      idle = gauge()
      assert attr(idle, ".duel-gauge-body", "aria-current") == []
      assert count(idle, "svg") == 0
    end

    test "a long name is kept whole in the markup and title, the CSS truncates it" do
      name = String.duplicate("Very long name ", 10)
      html = gauge(name: name)
      assert text(html, ".duel-gauge-name") == name
      assert attr(html, ".duel-gauge-name", "title") == [name]
      assert @css =~ "text-overflow: ellipsis"
    end
  end

  describe "atk_label" do
    test "is a pill, with the value after it" do
      html = render_component(&atk_label/1, value: "1600")
      assert text(html, ".duel-atk-pill") == "ATK"
      assert text(html, ".duel-atk-value") == "1600"
      assert count(render_component(&atk_label/1, []), ".duel-atk-value") == 0
    end
  end

  describe "synchro_ring" do
    test "uses the shared symbol and wraps its content" do
      html = render_component(&synchro_ring/1, inner_block: [])
      assert attr(html, "svg use", "href") == ["#duel-ring"]
      assert attr(html, "svg", "aria-hidden") == ["true"]
    end

    test "the symbol in the root layout has 12 identical dashes" do
      layout =
        File.read!(
          Path.expand(
            "../../../lib/millennium_quiz_web/components/layouts/root.html.heex",
            __DIR__
          )
        )

      assert [_, circle] = Regex.run(~r/<symbol id="duel-ring".*?(<circle.*?\/>)/s, layout)
      assert circle =~ ~s(pathLength="96")
      assert circle =~ ~s(stroke-dasharray="5 3")

      # one dash + one gap = 8 of 96: 12 dashes, all the same, no seam
      assert 96 / (5 + 3) == 12.0
    end

    test "the symbol is in every page", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)
      assert count(html, "symbol#duel-ring") == 1
    end
  end

  describe "orb_rail" do
    test "has one block per question: answered, the current orb, upcoming" do
      html = render_component(&orb_rail/1, total: 16, current: 3)
      assert count(html, ".duel-rail-block") == 16
      assert count(html, ~s(.duel-rail-block[data-state="answered"])) == 2
      assert count(html, ~s(.duel-rail-block[data-state="current"])) == 1
      assert count(html, ~s(.duel-rail-block[data-state="upcoming"])) == 13
      assert attr(html, ".duel-rail", "role") == ["progressbar"]
      assert attr(html, ".duel-rail", "aria-valuenow") == ["3"]
      assert attr(html, ".duel-rail", "aria-valuetext") == ["Question 3 of 16"]
    end

    test "the current question is clamped into the rail" do
      html = render_component(&orb_rail/1, total: 4, current: 9)
      assert count(html, ~s(.duel-rail-block[data-state="answered"])) == 3
      assert count(html, ~s(.duel-rail-block[data-state="current"])) == 1
    end
  end

  describe "contrast of the colours the components add" do
    defp tokens(theme) do
      selector =
        case theme do
          "duel-dark" -> "[data-theme=duel-dark]"
          "duel-light" -> ":where(:root), [data-theme=duel-light]"
        end

      [_, block] = Regex.run(~r/^#{Regex.escape(selector)} \{(.*?)\n\}/ms, @css)

      ~r/--duel-([a-z0-9-]+): (#[0-9a-f]{6});/
      |> Regex.scan(block)
      |> Map.new(fn [_, key, hex] -> {key, hex} end)
    end

    defp theme(name) do
      [_, block] = Regex.run(~r/name: "#{name}";(.*?)\n\}/s, @css)

      ~r/--color-([a-z0-9-]+): (#[0-9a-f]{6}|oklch\([^)]*\));/
      |> Regex.scan(block)
      |> Map.new(fn [_, key, value] -> {key, to_hex(value)} end)
    end

    defp to_hex("#" <> _ = hex), do: hex

    defp to_hex("oklch(" <> rest) do
      [l, c, h] =
        rest |> String.trim_trailing(")") |> String.split(" ", trim: true) |> Enum.map(&number/1)

      # oklab -> linear sRGB -> sRGB (Bjorn Ottosson's matrices)
      l = l / 100
      a = c * :math.cos(h * :math.pi() / 180)
      b = c * :math.sin(h * :math.pi() / 180)
      l_ = :math.pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
      m_ = :math.pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
      s_ = :math.pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)

      [
        4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_,
        -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_,
        -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_
      ]
      |> Enum.map(fn v ->
        v = v |> max(0.0) |> min(1.0)
        v = if v <= 0.0031308, do: 12.92 * v, else: 1.055 * :math.pow(v, 1 / 2.4) - 0.055
        v |> Kernel.*(255) |> round() |> Integer.to_string(16) |> String.pad_leading(2, "0")
      end)
      |> then(&("#" <> Enum.join(&1)))
      |> String.downcase()
    end

    defp number(text) do
      text
      |> String.trim_trailing("%")
      |> then(&if &1 =~ ".", do: &1, else: &1 <> ".0")
      |> String.to_float()
    end

    defp channel(hex, from) do
      c = hex |> binary_part(from, 2) |> String.to_integer(16) |> Kernel./(255)
      if c <= 0.03928, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
    end

    defp luminance(hex),
      do: 0.2126 * channel(hex, 1) + 0.7152 * channel(hex, 3) + 0.0722 * channel(hex, 5)

    defp ratio(a, b) do
      {la, lb} = {luminance(a), luminance(b)}
      (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    end

    for name <- ["duel-dark", "duel-light"] do
      test "#{name}: number, labels, damage, K.O. and the ring are readable" do
        t = tokens(unquote(name))
        c = theme(unquote(name))

        # text on the number plate (base-200) and on the panel (base-100)
        text_pairs =
          for bg <- ["base-200", "base-100"],
              fg <- [t["num"], t["ko"], t["p1"], t["p2"], t["p3"], t["p4"], c["error"]],
              do: {fg, c[bg]}

        # the K.O. badge text on its own background
        text_pairs = [{t["ko-text"], c["error"]} | text_pairs]

        for {fg, bg} <- text_pairs do
          assert ratio(fg, bg) >= 4.5, "#{fg} on #{bg}: #{Float.round(ratio(fg, bg), 2)}:1"
        end

        # parts of the UI: the Synchro ring and the player colours as bar fill
        for fg <- [t["sync"], t["p1"], t["p2"], t["p3"], t["p4"]],
            bg <- [c["base-100"], c["base-300"]] do
          assert ratio(fg, bg) >= 3.0, "#{fg} on #{bg}: #{Float.round(ratio(fg, bg), 2)}:1"
        end
      end
    end
  end
end
