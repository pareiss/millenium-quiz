defmodule MillenniumQuizWeb.CardComponents do
  @moduledoc """
  Yu-Gi-Oh! cards drawn with HTML and CSS from the card pool's data: frame,
  name, Attribute, Level/Rank, artwork, Link Arrows, Pendulum Scales, text
  and stats.

  Nothing is taken from Konami's card designs: the frames are CSS gradients
  (`.mq-card` in `app.css`) and the icons are SVGs drawn for this app. Sizes
  are relative to the card's width, so the same card works as a thumbnail
  and enlarged.
  """
  use MillenniumQuizWeb, :html

  @frames ~w(normal effect ritual fusion synchro xyz link token spell trap)

  # YAML Yugi's arrows, by position around the artwork.
  @link_arrows [
    {"↖", "top-left"},
    {"⬆", "top"},
    {"↗", "top-right"},
    {"⬅", "left"},
    {"➡", "right"},
    {"↙", "bottom-left"},
    {"⬇", "bottom"},
    {"↘", "bottom-right"}
  ]

  @doc """
  A card as printed (a `t:MillenniumQuiz.Game.card/0`). Cards from older game
  snapshots have no details; they get a plain frame and no artwork.

  `size` is `"small"` (the text box is cut off) or `"large"` (it scrolls).
  The width comes from the caller, e.g. `class="w-44"`.

  Long texts are set smaller, like on real cards. With `on_text`, the text
  box and the Pendulum box become one button that sends `on_text` (with
  `phx-value-card={text_value}`) to show the texts in a bigger panel.
  """
  attr :card, :map, required: true
  attr :size, :string, default: "small", values: ~w(small large)
  attr :on_text, :string, default: nil, doc: "event that shows a long text in a panel"
  attr :text_value, :any, default: nil, doc: "sent as `card` with `on_text`"
  attr :class, :any, default: nil
  attr :rest, :global

  def card(assigns) do
    card = assigns.card

    assigns =
      assigns
      |> assign(:frame, frame(card))
      |> assign(:pendulum?, pendulum?(card))
      |> assign(:spell_trap?, spell_trap?(card))
      |> assign(:link?, frame(card) == "link")
      |> assign(:arrows, Enum.map(card[:link_arrows] || [], &String.trim(&1, "\uFE0F")))
      |> assign(:read, read_attrs(assigns.on_text, assigns.text_value, card.name))

    ~H"""
    <div class={["mq-card", "mq-card--#{@size}", @class]} {@rest}>
      <div
        class="mq-card__face"
        data-frame={@frame}
        data-pendulum={@pendulum?}
      >
        <div class={["mq-card__name", name_size(@card.name)]}>
          <span class="mq-card__title" title={@card.name}>{@card.name}</span>
          <.attribute_icon :if={@card[:attribute]} attribute={@card.attribute} class="mq-card__attr" />
          <.attribute_icon :if={@spell_trap?} attribute={kind(@card)} class="mq-card__attr" />
        </div>

        <div :if={@spell_trap?} class="mq-card__line">
          [{kind(@card)} Card<span
            :if={@card[:property] not in [nil, "Normal"]}
            class="mq-card__property"
            title={"#{@card.property} #{kind(@card)}"}
          ><.property_icon property={@card.property} label={"#{@card.property} #{kind(@card)}"} /></span>]
        </div>
        <div
          :if={not @spell_trap? and not @link?}
          class={["mq-card__stars", @card[:rank] && "mq-card__stars--rank"]}
          title={stars_label(@card)}
        >
          <.level_star :for={_ <- stars(@card)} rank={not is_nil(@card[:rank])} />
        </div>

        <div class="mq-card__art">
          <img
            :if={@card[:id]}
            src={~p"/cards/#{@card.id}/artwork"}
            alt=""
            loading="lazy"
            decoding="async"
          />
          <svg
            :for={{arrow, position} <- link_arrows()}
            :if={@link?}
            viewBox="0 0 20 10"
            class={[
              "mq-card__arrow mq-card__arrow--#{position}",
              arrow in @arrows && "is-active"
            ]}
            aria-hidden="true"
          >
            <polygon points="10,1 19,9 1,9" />
          </svg>
        </div>

        <%!-- one clickable area for the Pendulum box and the text box --%>
        <div class={["mq-card__texts", @read != %{} && "is-readable"]} {@read}>
          <div :if={@pendulum?} class="mq-card__pendulum">
            <span class="mq-card__scale mq-card__scale--left" title="Pendulum Scale">
              <.scale_gem side="left" class="mq-card__gem" />
              {@card[:pendulum_scale]}
            </span>
            <p class={["mq-card__pendulum-text", text_size(@card[:pendulum_text], 90)]}>
              {@card[:pendulum_text]}
            </p>
            <span class="mq-card__scale mq-card__scale--right" title="Pendulum Scale">
              <.scale_gem side="right" class="mq-card__gem" />
              {@card[:pendulum_scale]}
            </span>
          </div>

          <div class={["mq-card__text", text_size(@card.text, 160)]}>
            <p :if={@card[:monster_type_line]} class="mq-card__type">[{@card.monster_type_line}]</p>
            <p class="mq-card__body">{@card.text}</p>
            <p :if={@card[:atk]} class="mq-card__stats">
              <span>ATK/{@card.atk}</span>
              <span :if={@link?}>LINK-{length(@arrows)}</span>
              <span :if={!@link?}>DEF/{@card.def}</span>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  A card enlarged in a dialog. Esc, the backdrop and the close button send
  `on_close`.
  """
  attr :id, :string, required: true
  attr :card, :map, required: true
  attr :on_close, :string, required: true
  attr :on_text, :string, default: nil, doc: "see `card/1`"
  attr :text_value, :any, default: nil
  slot :inner_block, doc: "shown below the card, e.g. credits"

  def card_dialog(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-50 grid place-items-center overflow-y-auto p-4"
      role="dialog"
      aria-modal="true"
      aria-label={@card.name}
      phx-window-keydown={@on_close}
      phx-key="escape"
      phx-mounted={JS.focus(to: "##{@id}-close")}
    >
      <div class="fixed inset-0 bg-black/65 backdrop-blur-sm" phx-click={@on_close} />
      <div class="relative flex w-[min(26rem,100%)] flex-col items-center gap-3 reveal-pop">
        <button
          type="button"
          id={"#{@id}-close"}
          class="btn btn-circle btn-sm absolute -top-2 -right-2 z-10 shadow"
          phx-click={@on_close}
          aria-label="Close"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
        <.card
          card={@card}
          size="large"
          class="w-full"
          on_text={@on_text}
          text_value={@text_value}
        />
        <p :if={@card.set} class="text-center text-sm text-white/90">As printed in {@card.set}</p>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  The texts of a card in a readable panel: name, type line, Pendulum Effect,
  text and stats. Esc, the backdrop and the close button send `on_close`.

  With `on_back`, a click on the panel sends `on_back` (with
  `phx-value-card={back_value}`), e.g. to go back to the enlarged card.
  """
  attr :id, :string, required: true
  attr :card, :map, required: true
  attr :on_close, :string, required: true
  attr :on_back, :string, default: nil
  attr :back_value, :any, default: nil
  slot :inner_block, doc: "shown below the text, e.g. credits"

  def card_text_dialog(assigns) do
    assigns =
      assign(assigns,
        link?: frame(assigns.card) == "link",
        arrows: Enum.map(assigns.card[:link_arrows] || [], &String.trim(&1, "\uFE0F"))
      )

    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-50 grid place-items-center overflow-y-auto p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      phx-window-keydown={@on_close}
      phx-key="escape"
      phx-mounted={JS.focus(to: "##{@id}-close")}
    >
      <div class="fixed inset-0 bg-black/65 backdrop-blur-sm" phx-click={@on_close} />
      <div class="relative flex w-[min(36rem,100%)] flex-col items-center gap-3 reveal-pop">
        <article
          class={[
            "mq-card-panel relative w-full",
            @on_back && "cursor-zoom-out"
          ]}
          data-frame={frame(@card)}
          phx-click={@on_back}
          phx-value-card={@on_back && @back_value}
          title={@on_back && "Back to the card"}
        >
          <%!-- For keyboards; mice can click anywhere on the panel --%>
          <button
            :if={@on_back}
            type="button"
            id={"#{@id}-back"}
            phx-click={@on_back}
            phx-value-card={@back_value}
            class="sr-only focus-visible:not-sr-only focus-visible:absolute focus-visible:-top-2 focus-visible:left-2 focus-visible:z-10 focus-visible:rounded-field focus-visible:bg-primary focus-visible:px-2 focus-visible:py-1 focus-visible:text-sm focus-visible:font-semibold focus-visible:text-primary-content"
          >
            Back to the card
          </button>
          <button
            type="button"
            id={"#{@id}-close"}
            class="btn btn-circle btn-sm absolute -top-2 -right-2 z-10 shadow"
            phx-click={@on_close}
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
          <header class="mq-card-panel__name">
            <h2 id={"#{@id}-title"}>{@card.name}</h2>
            <p :if={stars_label(@card)} class="mq-card-panel__stars" title={stars_label(@card)}>
              <span :if={(@card[:level] || @card[:rank]) != 1}>{@card[:level] || @card[:rank]}</span>
              <.level_star rank={not is_nil(@card[:rank])} class="size-7" />
              <span class="sr-only">{stars_label(@card)}</span>
            </p>
            <p :if={@link?} class="mq-card-panel__stars" title={link_label(@arrows)}>
              <.link_arrow
                :for={position <- lit_positions(@arrows)}
                position={position}
                class="size-6"
              />
              <span class="sr-only">{link_label(@arrows)}</span>
            </p>
            <span
              :if={kind(@card) in ["Spell", "Trap"] and @card[:property] not in [nil, "Normal"]}
              class="mq-card-panel__property"
              title={"#{@card.property} #{kind(@card)}"}
            ><.property_icon
              property={@card.property}
              label={"#{@card.property} #{kind(@card)}"}
              class="size-7"
            /></span>
            <.attribute_icon
              :if={@card[:attribute]}
              attribute={@card.attribute}
              class="size-8 shrink-0 cursor-help"
            />
            <.attribute_icon
              :if={kind(@card) in ["Spell", "Trap"]}
              attribute={kind(@card)}
              class="size-8 shrink-0 cursor-help"
            />
          </header>
          <div class="mq-card-panel__body">
            <p :if={@card[:monster_type_line]} class="font-bold">[{@card.monster_type_line}]</p>
            <p :if={kind(@card) in ["Spell", "Trap"]} class="font-bold">
              [{if @card[:property] in [nil, "Normal"], do: "Normal", else: @card.property} {kind(
                @card
              )}]
            </p>
            <section :if={@card[:pendulum_text]} class="mq-card-panel__pendulum">
              <h3>
                <span>Pendulum Effect</span>
                <span class="mq-card-panel__scale" title="Pendulum Scale">
                  <.scale_gem side="left" class="h-4 w-5" /> Scale {@card[:pendulum_scale]}
                  <.scale_gem side="right" class="h-4 w-5" />
                </span>
              </h3>
              <p>{@card.pendulum_text}</p>
            </section>
            <p class="whitespace-pre-line">{@card.text}</p>
            <p :if={@card[:atk]} class="mq-card-panel__stats">
              <span>ATK/{@card.atk}</span>
              <span :if={@link?}>LINK-{length(@card[:link_arrows] || [])}</span>
              <span :if={!@link?}>DEF/{@card.def}</span>
            </p>
          </div>
        </article>
        <%!-- outside the panel, so its links don't also go back to the card --%>
        <p :if={@card.set} class="text-center text-sm text-white/90">As printed in {@card.set}</p>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  ## Icons

  # Attribute and Spell/Trap spheres, drawn after the real icons: a glossy
  # marbled sphere with the kanji and the English name. Per key: kanji,
  # label, sphere colours (light, mid, dark), marble colour, gold ring?
  @attribute_icons %{
    "DARK" => {"闇", "DARK", {"#c27ae0", "#6b2a8f", "#1d0a2c"}, "#c8304e", false},
    "LIGHT" => {"光", "LIGHT", {"#e9d7a6", "#6e5222", "#1c1206"}, "#f3dc8c", true},
    "EARTH" => {"地", "EARTH", {"#9a9a9a", "#3b3b3b", "#0b0b0b"}, "#777777", false},
    "WATER" => {"水", "WATER", {"#a6e4ff", "#1d8fe2", "#0a347a"}, "#d4f4ff", false},
    "FIRE" => {"炎", "FIRE", {"#ff9a7a", "#e1241b", "#650906"}, "#ffb44a", false},
    "WIND" => {"風", "WIND", {"#a8ea96", "#2f9a3a", "#0b3f14"}, "#c6f5b0", false},
    "DIVINE" => {"神", "DIVINE", {"#e2cf98", "#5a4520", "#170f05"}, "#e8c86a", true},
    "Spell" => {"魔", "SPELL", {"#a6e8f0", "#2a90c0", "#0a2c52"}, "#061c46", false},
    "Trap" => {"罠", "TRAP", {"#ff9ccc", "#c0307e", "#4a0a2c"}, "#2a3fb0", false}
  }

  @doc "An Attribute (or Spell/Trap) sphere with its kanji and name."
  attr :attribute, :string, required: true
  attr :class, :any, default: nil

  def attribute_icon(assigns) do
    {glyph, label, {light, mid, dark}, marble, ring?} =
      Map.get(
        @attribute_icons,
        assigns.attribute,
        {"?", "", {"#a8a29e", "#57534e", "#1c1917"}, "#78716c", false}
      )

    assigns =
      assign(assigns,
        # gradient ids must be unique on the page (a card can be shown twice)
        id: "mq-attr-#{String.downcase(label)}-#{System.unique_integer([:positive])}",
        glyph: glyph,
        label: label,
        light: light,
        mid: mid,
        dark: dark,
        marble: marble,
        ring?: ring?,
        stripes?: assigns.attribute == "Spell"
      )

    ~H"""
    <svg viewBox="0 0 32 32" class={@class} role="img" aria-label={@attribute}>
      <title>{@attribute}</title>
      <defs>
        <radialGradient id={"#{@id}-ball"} cx="38%" cy="32%" r="72%">
          <stop offset="0" stop-color={@light} />
          <stop offset="0.5" stop-color={@mid} />
          <stop offset="1" stop-color={@dark} />
        </radialGradient>
        <radialGradient id={"#{@id}-shine"} cx="50%" cy="50%" r="50%">
          <stop offset="0" stop-color="#fff" stop-opacity="0.55" />
          <stop offset="1" stop-color="#fff" stop-opacity="0" />
        </radialGradient>
        <filter id={"#{@id}-marble"} x="0" y="0" width="100%" height="100%">
          <feTurbulence type="fractalNoise" baseFrequency="0.09 0.16" numOctaves="2" seed="4" />
          <feColorMatrix values={"0 0 0 0 #{rgb(@marble, 0)} 0 0 0 0 #{rgb(@marble, 1)} 0 0 0 0 #{rgb(@marble, 2)} 2.6 0 0 0 -1.15"} />
        </filter>
        <radialGradient id={"#{@id}-red"} cx="50%" cy="50%" r="50%">
          <stop offset="0" stop-color="#f22a3a" />
          <stop offset="0.65" stop-color="#cc1a2e" stop-opacity="0.9" />
          <stop offset="1" stop-color="#c0182c" stop-opacity="0" />
        </radialGradient>
        <clipPath id={"#{@id}-clip"}><circle cx="16" cy="16" r="15" /></clipPath>
      </defs>
      <circle cx="16" cy="16" r="15" fill={"url(##{@id}-ball)"} />
      <g clip-path={"url(##{@id}-clip)"}>
        <rect :if={!@stripes?} width="32" height="32" filter={"url(##{@id}-marble)"} opacity="0.7" />
        <%!-- Spell: curved bands from the top left to the bottom right, arcs
             around a point beyond the top right of the sphere --%>
        <g :if={@stripes?} fill="none" stroke={@marble} stroke-width="1.7" stroke-opacity="0.85">
          <circle :for={r <- 12..54//3} cx="36" cy="-6" r={r} />
        </g>
        <%!-- DARK: a crimson top above a dark band --%>
        <g :if={@attribute == "DARK"}>
          <ellipse cx="16" cy="6" rx="16" ry="10.5" fill={"url(##{@id}-red)"} />
          <path d="M0 15 Q16 10 32 13 L32 17 Q16 14 0 19 Z" fill="#12061c" fill-opacity="0.55" />
        </g>
      </g>
      <circle
        :if={@ring?}
        cx="16"
        cy="16"
        r="14"
        fill="none"
        stroke="#f5d77a"
        stroke-width="1.8"
        stroke-opacity="0.9"
      />
      <ellipse
        cx="11"
        cy="9.5"
        rx="7"
        ry="4.2"
        transform="rotate(-28 11 9.5)"
        fill={"url(##{@id}-shine)"}
      />
      <circle cx="16" cy="16" r="15" fill="none" stroke="#120d0a" stroke-width="0.9" />
      <text
        x="16"
        y="8.6"
        text-anchor="middle"
        font-family="ui-serif, Georgia, serif"
        font-size={if String.length(@label) > 5, do: "3.9", else: "4.4"}
        font-weight="700"
        letter-spacing="0.15"
        fill="#fff"
        stroke="#1c1917"
        stroke-width="0.35"
        paint-order="stroke"
      >
        {@label}
      </text>
      <text
        x="16"
        y="23.6"
        text-anchor="middle"
        font-size="14.5"
        font-weight="700"
        fill="#fff"
        stroke="#1c1917"
        stroke-width="0.6"
        paint-order="stroke"
      >
        {@glyph}
      </text>
    </svg>
    """
  end

  # One channel of a "#rrggbb" colour, 0..1, for an feColorMatrix.
  defp rgb("#" <> hex, channel) do
    hex
    |> String.slice(channel * 2, 2)
    |> String.to_integer(16)
    |> Kernel./(255)
    |> Float.round(3)
  end

  @doc """
  A Pendulum Scale crystal: a faceted gem, blue on the left and red on the
  right, its outer point reaching further out like on real cards.
  """
  attr :side, :string, required: true, values: ~w(left right)
  attr :class, :any, default: nil

  def scale_gem(assigns) do
    {highlight, light, mid, dark, edge} =
      if assigns.side == "left",
        do: {"#eaf5ff", "#9fd0ff", "#3d84f0", "#1640a8", "#0b2a6e"},
        else: {"#ffe6ea", "#ff9aa8", "#e8364c", "#8a0f1e", "#5a0610"}

    # outer point, top, inner point, bottom and the centre of the facets
    {o, i, c} = if assigns.side == "left", do: {0, 10.4, 6.4}, else: {12, 1.6, 5.6}
    t = if assigns.side == "left", do: 6.8, else: 5.2

    assigns =
      assign(assigns,
        highlight: highlight,
        light: light,
        mid: mid,
        dark: dark,
        edge: edge,
        o: o,
        i: i,
        c: c,
        t: t
      )

    ~H"""
    <svg viewBox="0 0 12 10" class={@class} aria-hidden="true">
      <g stroke={@edge} stroke-width="0.2" stroke-linejoin="round">
        <polygon points={"#{@o},5 #{@t},0.4 #{@c},4.4"} fill={@light} />
        <polygon points={"#{@t},0.4 #{@i},5 #{@c},4.4"} fill={@highlight} />
        <polygon points={"#{@i},5 #{@t},9.6 #{@c},4.4"} fill={@dark} />
        <polygon points={"#{@t},9.6 #{@o},5 #{@c},4.4"} fill={@mid} />
      </g>
      <polygon
        points={"#{(@o + @c) / 2},3.6 #{@t},1.4 #{(@t + @c) / 2},3"}
        fill="#fff"
        fill-opacity="0.75"
      />
    </svg>
    """
  end

  @doc "One lit Link Arrow pointing to `position` (e.g. `\"bottom-left\"`)."
  attr :position, :string, required: true
  attr :class, :any, default: nil

  def link_arrow(assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" class={["mq-link-arrow", @class]} aria-hidden="true">
      <%!-- the same triangle as the arrows on the card; each turned arrow is
           moved so its outline is centred, putting all of them on one line --%>
      <polygon
        points="12,5.6 22.8,15.2 1.2,15.2"
        transform={"#{arrow_centring(@position)} rotate(#{arrow_turn(@position)} 12 12)"}
      />
    </svg>
    """
  end

  @doc "One Level star (red-orange disc) or Rank star (black disc)."
  attr :rank, :boolean, default: false
  attr :class, :any, default: "mq-card__star"

  def level_star(assigns) do
    {light, mid, dark, rim} =
      if assigns.rank,
        do: {"#8f8f8f", "#3a3a3a", "#0b0b0b", "#050505"},
        else: {"#ffc27a", "#e4521f", "#7e1607", "#4a0c03"}

    assigns =
      assign(assigns,
        id: "mq-star-#{System.unique_integer([:positive])}",
        light: light,
        mid: mid,
        dark: dark,
        rim: rim
      )

    ~H"""
    <svg viewBox="0 0 32 32" class={@class} aria-hidden="true">
      <defs>
        <radialGradient id={"#{@id}-ball"} cx="38%" cy="32%" r="72%">
          <stop offset="0" stop-color={@light} />
          <stop offset="0.55" stop-color={@mid} />
          <stop offset="1" stop-color={@dark} />
        </radialGradient>
        <linearGradient id={"#{@id}-gold"} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#fff6b0" />
          <stop offset="0.5" stop-color="#f7c600" />
          <stop offset="1" stop-color="#d48d00" />
        </linearGradient>
      </defs>
      <circle cx="16" cy="16" r="15" fill={"url(##{@id}-ball)"} stroke={@rim} stroke-width="1" />
      <polygon
        points="16,5 19.1,12.5 27,12.9 20.9,18 23,25.8 16,21.4 9,25.8 11.1,18 5,12.9 12.9,12.5"
        fill={"url(##{@id}-gold)"}
        stroke="#b86e00"
        stroke-width="0.5"
        stroke-linejoin="round"
      />
      <ellipse
        cx="11"
        cy="8.5"
        rx="6"
        ry="3"
        transform="rotate(-28 11 8.5)"
        fill="#fff"
        fill-opacity="0.28"
      />
    </svg>
    """
  end

  @doc "A Spell/Trap property glyph: Quick-Play, Continuous, Equip, Field, Ritual or Counter."
  attr :property, :string, required: true
  attr :label, :string, default: nil, doc: "defaults to the property"
  attr :class, :any, default: nil

  def property_icon(assigns) do
    assigns =
      assign(assigns,
        label: assigns.label || assigns.property,
        # gradient and filter ids must be unique on the page
        id: "mq-prop-#{System.unique_integer([:positive])}"
      )

    ~H"""
    <svg viewBox="0 0 24 24" class={@class} role="img" aria-label={@label}>
      <title>{@label}</title>
      <defs>
        <radialGradient id={"#{@id}-disc"} cx="40%" cy="35%" r="70%">
          <stop offset="0" stop-color="#6b4a30" />
          <stop offset="0.55" stop-color="#2e1f14" />
          <stop offset="1" stop-color="#0e0906" />
        </radialGradient>
        <filter id={"#{@id}-rust"} x="0" y="0" width="100%" height="100%">
          <feTurbulence type="fractalNoise" baseFrequency="0.22" numOctaves="2" seed="9" />
          <feColorMatrix values="0 0 0 0 0.62 0 0 0 0 0.45 0 0 0 0 0.3 2.4 0 0 0 -1.1" />
        </filter>
        <linearGradient id={"#{@id}-silver"} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#fbf9f4" />
          <stop offset="1" stop-color="#bdb6aa" />
        </linearGradient>
        <clipPath id={"#{@id}-in"}><circle cx="12" cy="12" r="9.7" /></clipPath>
      </defs>
      <%!-- a round badge as on real cards: dark, rusty marble in a silver ring --%>
      <circle cx="12" cy="12" r="11" fill={"url(##{@id}-disc)"} />
      <rect
        width="24"
        height="24"
        filter={"url(##{@id}-rust)"}
        opacity="0.6"
        clip-path={"url(##{@id}-in)"}
      />
      <circle cx="12" cy="12" r="10.4" fill="none" stroke={"url(##{@id}-silver)"} stroke-width="1.5" />
      <circle cx="12" cy="12" r="11.5" fill="none" stroke="#1a120c" stroke-width="0.8" />
      <g
        fill={"url(##{@id}-silver)"}
        stroke="#1a120c"
        stroke-width="0.6"
        stroke-linejoin="round"
        clip-path={"url(##{@id}-in)"}
      >
        <%= case @property do %>
          <% "Quick-Play" -> %>
            <g transform="translate(12 12) scale(0.96) translate(-12 -12)">
              <path d="M13.5 2 4.5 13.5h6.5L9.5 22l10-12.5h-6.5z" />
            </g>
          <% "Continuous" -> %>
            <%!-- a thick infinity sign, its loops cut out --%>
            <g transform="translate(12 12) scale(0.78) translate(-12 -12)">
              <path
                fill-rule="evenodd"
                d="M6.5 6.5a5.5 5.5 0 1 0 0 11c2.4 0 3.8-1.6 5.5-3.6 1.7 2 3.1 3.6 5.5 3.6a5.5 5.5 0 1 0 0-11c-2.4 0-3.8 1.6-5.5 3.6-1.7-2-3.1-3.6-5.5-3.6zM6.5 9.4a2.6 2.6 0 1 0 0 5.2c1.2 0 2.2-1.2 3.6-2.6-1.4-1.4-2.4-2.6-3.6-2.6zM17.5 9.4c-1.2 0-2.2 1.2-3.6 2.6 1.4 1.4 2.4 2.6 3.6 2.6a2.6 2.6 0 1 0 0-5.2z"
              />
            </g>
          <% "Equip" -> %>
            <%!-- a cross with square arms reaching the ring --%>
            <path d="M10 1h4v9h9v4h-9v9h-4v-9H1v-4h9z" />
          <% "Field" -> %>
            <%!-- a four-pointed star, faceted: each point is split along its
                 middle into a silver half and an open, silver-edged half (the badge
                 shows through), turning the same way on every point, for a 3D look --%>
            <g transform="translate(12 12) scale(0.96) translate(-12 -12)">
              <polygon points="12,12 9.4,9.4 12,1.5" />
              <polygon
                points="12,12 12,1.5 14.6,9.4"
                fill="none"
                stroke={"url(##{@id}-silver)"}
                stroke-width="0.8"
              />
              <polygon points="12,12 14.6,9.4 22.5,12" />
              <polygon
                points="12,12 22.5,12 14.6,14.6"
                fill="none"
                stroke={"url(##{@id}-silver)"}
                stroke-width="0.8"
              />
              <polygon points="12,12 14.6,14.6 12,22.5" />
              <polygon
                points="12,12 12,22.5 9.4,14.6"
                fill="none"
                stroke={"url(##{@id}-silver)"}
                stroke-width="0.8"
              />
              <polygon points="12,12 9.4,14.6 1.5,12" />
              <polygon
                points="12,12 1.5,12 9.4,9.4"
                fill="none"
                stroke={"url(##{@id}-silver)"}
                stroke-width="0.8"
              />
            </g>
          <% "Ritual" -> %>
            <%!-- a flame: a small tongue on the left, a tall one sweeping right
                 from its tip, a tongue on the right, and a small inner flame
                 cut out at the bottom --%>
            <g transform="translate(12 12) scale(0.9) translate(-12 -12)">
              <path
                fill-rule="evenodd"
                d="M12 21.2C7 21.2 3.1 18.9 3.1 15.2C3.1 12.4 4 10.2 5.2 8.2C5.6 10.4 6.2 12.6 7.1 14.6C7.6 12 7.9 7.6 7.6 2.2C11.4 4 14.4 7.2 16.4 11.2C16.3 9.4 16.4 7.6 16.9 5.8C19.6 8.4 20.9 11.8 20.9 15.2C20.9 18.9 17 21.2 12 21.2ZM12.3 13.4C10.8 15 10 16.9 10.3 19.2C11.5 19.9 13 19.9 14.2 19.2C14.3 18.3 14.1 17.4 13.8 17C13.5 17.5 13.2 17.7 12.9 17.5C12.9 16 12.7 14.6 12.3 13.4Z"
              />
            </g>
          <% "Counter" -> %>
            <%!-- a thick arrow: it starts as a point at the top right, runs
                 down and hooks sharply to the left into a large head --%>
            <g transform="translate(12 12) scale(0.76) translate(-12 -12)">
              <path d="M19.6 2.8C21.7 5.6 22.1 10.2 20.6 13.8C19.2 17.2 15.9 19.6 12.4 20L12.6 22.6L2.4 15.4L12.4 8.4L12.3 12.3C15 12.2 17.3 11.3 18.6 9.4C19.6 7.8 19.9 5.6 19.6 2.8Z" />
            </g>
          <% _ -> %>
            <circle cx="12" cy="12" r="3" />
        <% end %>
      </g>
    </svg>
    """
  end

  ## Helpers

  defp link_arrows, do: @link_arrows

  # Real cards set long texts smaller. `fits` is how many characters fit at
  # the normal size.
  defp text_size(nil, _fits), do: nil

  defp text_size(text, fits) do
    case String.length(text) / fits do
      r when r <= 1 -> nil
      r when r <= 1.4 -> "mq-text--s"
      r when r <= 1.9 -> "mq-text--xs"
      _ -> "mq-text--xxs"
    end
  end

  # Makes an element a button that shows the card's texts in a panel.
  defp read_attrs(nil, _value, _name), do: %{}

  defp read_attrs(event, value, name) do
    %{
      "phx-click" => event,
      "phx-value-card" => value,
      "phx-keydown" => event,
      "phx-key" => "Enter",
      "role" => "button",
      "tabindex" => "0",
      "aria-label" => "Read the texts of #{name}",
      "title" => "Read the texts"
    }
  end

  defp arrow_turn(position) do
    %{
      "top" => 0,
      "top-right" => 45,
      "right" => 90,
      "bottom-right" => 135,
      "bottom" => 180,
      "bottom-left" => 225,
      "left" => 270,
      "top-left" => 315
    }[position]
  end

  # Moves a turned panel arrow so its outline is centred in the icon.
  defp arrow_centring(position) do
    %{
      "top" => "translate(0.0 1.6)",
      "top-right" => "translate(2.26 -2.26)",
      "right" => "translate(-1.6 0.0)",
      "bottom-right" => "translate(2.26 2.26)",
      "bottom" => "translate(0.0 -1.6)",
      "bottom-left" => "translate(-2.26 2.26)",
      "left" => "translate(1.6 0.0)",
      "top-left" => "translate(-2.26 -2.26)"
    }[position]
  end

  # A Link monster's arrows, clockwise from the bottom: bottom, bottom
  # left, left, top left, top, top right, right, bottom right.
  defp lit_positions(arrows) do
    @link_arrows
    |> Enum.filter(fn {arrow, _} -> arrow in arrows end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(&rem(arrow_turn(&1) + 180, 360))
  end

  defp link_label(arrows) do
    names = arrows |> lit_positions() |> Enum.map(&String.replace(&1, "-", " "))

    "Link #{length(arrows)}: #{Enum.join(names, ", ")}"
  end

  defp stars_label(%{rank: rank}) when is_integer(rank), do: "Rank #{rank}"
  defp stars_label(%{level: level}) when is_integer(level), do: "Level #{level}"
  defp stars_label(_card), do: nil

  # Long names get a smaller font, like the condensed names on real cards.
  defp name_size(name) do
    case String.length(name || "") do
      n when n > 28 -> "mq-card__name--longer"
      n when n > 20 -> "mq-card__name--long"
      _ -> nil
    end
  end

  # "effect_pendulum" -> "effect"; old snapshots fall back on the card kind.
  defp frame(%{frame_type: "" <> type}) do
    base = String.replace_suffix(type, "_pendulum", "")
    if base in @frames, do: base, else: "unknown"
  end

  defp frame(card) do
    case kind(card) do
      "Spell" -> "spell"
      "Trap" -> "trap"
      _ -> "unknown"
    end
  end

  defp pendulum?(card),
    do:
      String.ends_with?(card[:frame_type] || "", "_pendulum") or not is_nil(card[:pendulum_scale])

  defp spell_trap?(card), do: kind(card) in ["Spell", "Trap"]

  defp kind(%{kind: kind}) when is_binary(kind), do: kind

  defp kind(card) do
    case card[:frame_type] do
      "spell" -> "Spell"
      "trap" -> "Trap"
      _ -> nil
    end
  end

  defp stars(card), do: List.duplicate(nil, min(card[:level] || card[:rank] || 0, 13))
end
