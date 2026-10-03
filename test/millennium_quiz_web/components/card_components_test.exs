defmodule MillenniumQuizWeb.CardComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import MillenniumQuizWeb.CardComponents

  @blank %{
    id: nil,
    name: nil,
    text: "",
    set: nil,
    kind: nil,
    property: nil,
    frame_type: nil,
    monster_type_line: nil,
    attribute: nil,
    level: nil,
    rank: nil,
    link_arrows: [],
    atk: nil,
    def: nil,
    pendulum_scale: nil,
    pendulum_text: nil
  }

  defp render_card(attrs, opts \\ []) do
    card = Map.merge(@blank, attrs)
    render_component(&card/1, [card: card] ++ opts) |> LazyHTML.from_fragment()
  end

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  defp text(doc, selector),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.text() |> String.trim()

  test "a monster has its frame, Attribute, Level stars, artwork, type line and stats" do
    doc =
      render_card(%{
        id: 12,
        name: "Dark Magician",
        text: "The ultimate wizard.",
        kind: "Monster",
        frame_type: "normal",
        monster_type_line: "Spellcaster / Normal",
        attribute: "DARK",
        level: 7,
        atk: "2500",
        def: "2100"
      })

    assert count(doc, ".mq-card__face[data-frame=normal]") == 1
    assert count(doc, ".mq-card__attr[aria-label=DARK]") == 1
    assert count(doc, ".mq-card__stars .mq-card__star") == 7
    assert count(doc, ".mq-card__stars--rank") == 0
    assert count(doc, ".mq-card__art img[src='/cards/12/artwork']") == 1
    assert text(doc, ".mq-card__type") == "[Spellcaster/Normal]"
    assert text(doc, ".mq-card__body") == "The ultimate wizard."
    assert text(doc, ".mq-card__stats") =~ ~r/ATK\/2500\s+DEF\/2100/
  end

  test "an Xyz Pendulum has Rank stars, two scales and its Pendulum Effect" do
    doc =
      render_card(%{
        name: "Plain Card",
        frame_type: "xyz_pendulum",
        kind: "Monster",
        rank: 4,
        pendulum_scale: 3,
        pendulum_text: "Once per turn: draw 1 card.",
        atk: "2000",
        def: "?"
      })

    assert count(doc, ".mq-card__face[data-frame=xyz][data-pendulum]") == 1
    assert count(doc, ".mq-card__stars--rank .mq-card__star") == 4
    assert count(doc, ".mq-card__scale") == 2
    assert text(doc, ".mq-card__scale--left") == "3"
    # no line break before the text: the paragraph keeps line breaks
    assert doc |> LazyHTML.query(".mq-card__pendulum-text") |> LazyHTML.text() ==
             "Once per turn: draw 1 card."
  end

  test "a Link monster shows its arrows and rating instead of stars and DEF" do
    doc =
      render_card(%{
        name: "Decode Talker",
        frame_type: "link",
        kind: "Monster",
        # YAML Yugi's arrows, one with an emoji variation selector
        link_arrows: ["↙", "⬆️", "↘"],
        atk: "2300"
      })

    assert count(doc, ".mq-card__stars") == 0
    assert count(doc, ".mq-card__arrow") == 8
    assert count(doc, ".mq-card__arrow.is-active") == 3
    assert count(doc, ".mq-card__arrow--top.is-active") == 1
    assert text(doc, ".mq-card__stats") =~ ~r/ATK\/2300\s+LINK-3/
    refute text(doc, ".mq-card__stats") =~ "DEF"
  end

  test "a Spell shows its kind and property icon, and no stats" do
    doc =
      render_card(%{
        name: "Mystical Space Typhoon",
        kind: "Spell",
        property: "Quick-Play",
        frame_type: "spell"
      })

    assert count(doc, ".mq-card__face[data-frame=spell]") == 1
    assert count(doc, ".mq-card__attr[aria-label=Spell]") == 1
    assert text(doc, ".mq-card__line") =~ "Spell Card"
    # the property icon has a hover text, like the Attribute disc
    assert count(
             doc,
             ".mq-card__property[title='Quick-Play Spell'] svg[aria-label='Quick-Play Spell']"
           ) == 1

    assert count(doc, ".mq-card__stats, .mq-card__stars, .mq-card__type") == 0

    normal = render_card(%{name: "Raigeki", kind: "Trap", property: "Normal", frame_type: "trap"})
    assert count(normal, ".mq-card__property") == 0
    assert count(normal, ".mq-card__attr[aria-label=Trap]") == 1
  end

  test "every Spell/Trap property has its own icon" do
    paths =
      for property <- ~w(Quick-Play Continuous Equip Field Ritual Counter) do
        doc = render_card(%{name: "X", kind: "Spell", property: property, frame_type: "spell"})
        assert count(doc, ".mq-card__property[title='#{property} Spell']") == 1
        doc |> LazyHTML.query(".mq-card__property svg") |> LazyHTML.to_html()
      end

    assert paths
           |> Enum.map(&String.replace(&1, ~r/aria-label="[^"]*"|<title>.*?<\/title>/, ""))
           |> Enum.uniq()
           |> length() == 6
  end

  test "Level and Rank stars say what they are on hover" do
    assert count(render_card(%{name: "X", level: 4}), ".mq-card__stars[title='Level 4']") == 1
    assert count(render_card(%{name: "X", rank: 4}), ".mq-card__stars[title='Rank 4']") == 1
  end

  test "long texts are set smaller" do
    short = render_card(%{name: "X", text: "Draw 2 cards."})
    assert count(short, ".mq-card__text") == 1
    assert count(short, ".mq-text--s, .mq-text--xs, .mq-text--xxs") == 0

    # 270 characters: 1.7 times what fits at the normal size
    long = render_card(%{name: "X", text: String.duplicate("Long effect text. ", 15)})
    assert count(long, ".mq-card__text.mq-text--xs") == 1

    pendulum =
      render_card(%{
        name: "X",
        text: "Short.",
        pendulum_scale: 4,
        pendulum_text: String.duplicate("Long effect text. ", 30)
      })

    assert count(pendulum, ".mq-card__pendulum-text.mq-text--xxs") == 1
  end

  test "with on_text, the text and Pendulum boxes are one button that opens the texts" do
    button =
      "[role=button][tabindex='0'][phx-click=read][phx-value-card='3'][phx-keydown=read][phx-key=Enter]"

    # every text, however short (Normal Monsters' flavor texts can be long too)
    short = render_card(%{name: "X", text: "Draw 2 cards."}, on_text: "read", text_value: 3)
    assert count(short, ".mq-card__texts.is-readable#{button} > .mq-card__text") == 1

    pendulum =
      render_card(%{name: "X", text: "Short.", pendulum_scale: 4, pendulum_text: "P."},
        on_text: "read",
        text_value: 3
      )

    assert count(pendulum, ".mq-card__texts.is-readable#{button} > .mq-card__pendulum") == 1
    assert count(pendulum, ".mq-card__texts.is-readable#{button} > .mq-card__text") == 1
    assert count(pendulum, "[phx-click]") == 1

    # without on_text nothing is clickable
    plain = render_card(%{name: "X", text: "Short.", pendulum_scale: 4, pendulum_text: "P."})
    assert count(plain, "[phx-click], .is-readable") == 0
  end

  test "the text panel shows every text of the card in a readable size" do
    card =
      Map.merge(@blank, %{
        name: "Odd-Eyes Pendulum Dragon",
        frame_type: "effect_pendulum",
        monster_type_line: "Dragon / Pendulum / Effect",
        attribute: "DARK",
        text: "Double damage.",
        pendulum_scale: 4,
        pendulum_text: "Reduce damage to 0.",
        atk: "2500",
        def: "2000",
        set: "Starter Deck"
      })

    html =
      render_component(&card_text_dialog/1,
        id: "text",
        card: card,
        on_close: "close",
        inner_block: []
      )

    doc = LazyHTML.from_fragment(html)

    assert count(
             doc,
             "#text[role=dialog][aria-labelledby=text-title][phx-window-keydown=close][phx-key=escape]"
           ) == 1

    assert count(doc, "#text [phx-click=close]") == 2
    assert count(doc, "#text .mq-card-panel[data-frame=effect]") == 1
    assert text(doc, "#text-title") == "Odd-Eyes Pendulum Dragon"
    assert text(doc, ".mq-card-panel__pendulum") =~ ~r/Scale 4\s+Reduce damage to 0\./
    # the scale between its blue and red crystal
    assert count(doc, ".mq-card-panel__scale > svg") == 2
    assert count(doc, ".mq-card-panel__scale > svg:first-child polygon[fill='#3d84f0']") == 1
    assert count(doc, ".mq-card-panel__scale > svg:last-child polygon[fill='#e8364c']") == 1
    assert html =~ "[Dragon / Pendulum / Effect]"
    assert html =~ "Double damage."
    assert text(doc, ".mq-card-panel__stats") =~ ~r/ATK\/2500\s+DEF\/2000/
    assert html =~ "As printed in Starter Deck"

    spell =
      Map.merge(@blank, %{name: "MST", kind: "Spell", property: "Quick-Play", text: "Destroy."})

    html =
      render_component(&card_text_dialog/1,
        id: "text",
        card: spell,
        on_close: "close",
        inner_block: []
      )

    assert html =~ "[Quick-Play Spell]"
    assert html =~ ~s(title="Quick-Play Spell")

    assert html
           |> LazyHTML.from_fragment()
           |> count("header .mq-card-panel__property[title='Quick-Play Spell'] svg") == 1

    normal = Map.put(spell, :property, "Normal")

    html =
      render_component(&card_text_dialog/1,
        id: "text",
        card: normal,
        on_close: "close",
        inner_block: []
      )

    refute html =~ "mq-card-panel__property"
  end

  test "with on_back, a click on the text panel goes back" do
    card = Map.merge(@blank, %{name: "X", text: "Y."})

    without =
      render_component(&card_text_dialog/1,
        id: "t",
        card: card,
        on_close: "close",
        inner_block: []
      )

    assert without |> LazyHTML.from_fragment() |> count("article[phx-click], #t-back") == 0

    doc =
      render_component(&card_text_dialog/1,
        id: "t",
        card: card,
        on_close: "close",
        on_back: "zoom",
        back_value: 2,
        inner_block: []
      )
      |> LazyHTML.from_fragment()

    assert count(doc, "article[phx-click=zoom][phx-value-card='2']") == 1
    assert count(doc, "#t-back[phx-click=zoom][phx-value-card='2']") == 1
    # closing still closes
    assert count(doc, "#t-close[phx-click=close]") == 1
  end

  test "the text panel's header shows the Level or Rank as a number and a star" do
    panel = fn attrs ->
      card =
        Map.merge(
          @blank,
          Map.merge(%{name: "X", monster_type_line: "Spellcaster / Normal"}, attrs)
        )

      render_component(&card_text_dialog/1,
        id: "text",
        card: card,
        on_close: "close",
        inner_block: []
      )
      |> LazyHTML.from_fragment()
    end

    seven = panel.(%{level: 7})
    assert count(seven, "header .mq-card-panel__stars[title='Level 7'] svg") == 1
    assert text(seven, ".mq-card-panel__stars span:not(.sr-only)") == "7"

    # a single star or Rank has no number
    one = panel.(%{rank: 1})
    assert count(one, ".mq-card-panel__stars[title='Rank 1'] svg") == 1
    assert count(one, ".mq-card-panel__stars span:not(.sr-only)") == 0

    # Link monsters show their lit arrows instead, clockwise from the bottom
    link = panel.(%{frame_type: "link", link_arrows: ["↙", "⬆\uFE0F", "↘"]})

    assert count(
             link,
             "header .mq-card-panel__stars[title='Link 3: bottom left, top, bottom right']"
           ) == 1

    turns =
      link
      |> LazyHTML.query(".mq-link-arrow polygon")
      |> Enum.map(&(LazyHTML.attribute(&1, "transform") |> hd()))
      |> Enum.map(&(Regex.run(~r/rotate\((\d+) /, &1) |> List.last()))

    assert turns == ["225", "0", "135"]
  end

  test "icons drawn twice on a page get their own gradient ids" do
    ids = fn html ->
      ~r/ id="([^"]+)"/ |> Regex.scan(html, capture: :all_but_first) |> List.flatten()
    end

    attr = fn -> render_component(&attribute_icon/1, attribute: "DARK") end
    star = fn -> render_component(&level_star/1, rank: false) end

    all = ids.(attr.()) ++ ids.(attr.()) ++ ids.(star.()) ++ ids.(star.())
    assert all != []
    assert length(all) == length(Enum.uniq(all))
  end

  test "long names are squeezed horizontally instead of shrunk" do
    squeeze = fn name ->
      render_card(%{name: name})
      |> LazyHTML.query(".mq-card__title > span")
      |> LazyHTML.attribute("style")
      |> hd()
    end

    assert squeeze.("Dark Magician") == "--squeeze: 1"
    # capitals count wider than small caps, spaces narrower
    assert squeeze.("Mystical Space Typhoon") == "--squeeze: 0.647"
    assert squeeze.("Odd-Eyes Pendulum Dragon") == "--squeeze: 0.6"
    # never narrower than half width
    assert squeeze.(String.duplicate("Long name ", 8)) == "--squeeze: 0.5"
  end

  test "a card from an old snapshot gets a plain frame and no artwork" do
    doc = render_card(%{name: "Monster Reborn", text: "Revive."})

    assert count(doc, ".mq-card__face[data-frame=unknown]") == 1
    assert count(doc, "img") == 0
    assert text(doc, ".mq-card__body") == "Revive."
  end

  test "the dialog closes on Esc, the backdrop and its close button" do
    card = Map.merge(@blank, %{name: "Monster Reborn", text: "Revive.", set: "Starter Deck"})

    html =
      render_component(&card_dialog/1, id: "zoom", card: card, on_close: "close", inner_block: [])

    doc = LazyHTML.from_fragment(html)

    assert count(doc, "#zoom[role=dialog][aria-modal=true][aria-label='Monster Reborn']") == 1
    assert count(doc, "#zoom[phx-window-keydown=close][phx-key=escape]") == 1
    assert count(doc, "#zoom [phx-click=close]") == 2
    assert count(doc, "#zoom .mq-card--large") == 1
    assert html =~ "As printed in Starter Deck"
  end
end
