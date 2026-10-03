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
          <span
            :for={{arrow, position} <- link_arrows()}
            :if={@link?}
            class={[
              "mq-card__arrow mq-card__arrow--#{position}",
              arrow in @arrows && "is-active"
            ]}
          />
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
        <p :if={@card.set} class="text-sm text-white/90">As printed in {@card.set}</p>
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
    assigns = assign(assigns, :link?, frame(assigns.card) == "link")

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
      <article
        class={[
          "mq-card-panel relative w-[min(36rem,100%)] reveal-pop",
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
            class="size-8 shrink-0"
          />
          <.attribute_icon
            :if={kind(@card) in ["Spell", "Trap"]}
            attribute={kind(@card)}
            class="size-8 shrink-0"
          />
        </header>
        <div class="mq-card-panel__body">
          <p :if={@card[:monster_type_line]} class="font-bold">[{@card.monster_type_line}]</p>
          <p :if={kind(@card) in ["Spell", "Trap"]} class="font-bold">
            [{if @card[:property] in [nil, "Normal"], do: "Normal", else: @card.property} {kind(@card)}]
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
        <p :if={@card.set} class="mt-3 text-sm text-white/90">As printed in {@card.set}</p>
        {render_slot(@inner_block)}
      </article>
    </div>
    """
  end

  ## Icons

  @attribute_icons %{
    "DARK" => {"闇", "#5b2a86"},
    "LIGHT" => {"光", "#c9a227"},
    "EARTH" => {"地", "#6f4e2e"},
    "WATER" => {"水", "#2770b8"},
    "FIRE" => {"炎", "#c63a22"},
    "WIND" => {"風", "#2f8a43"},
    "DIVINE" => {"神", "#a8842b"},
    "Spell" => {"魔", "#178a7a"},
    "Trap" => {"罠", "#a2306f"}
  }

  @doc "An Attribute (or Spell/Trap) disc with its kanji."
  attr :attribute, :string, required: true
  attr :class, :any, default: nil

  def attribute_icon(assigns) do
    {glyph, color} = Map.get(@attribute_icons, assigns.attribute, {"?", "#57534e"})
    assigns = assign(assigns, glyph: glyph, color: color)

    ~H"""
    <svg viewBox="0 0 32 32" class={@class} role="img" aria-label={@attribute}>
      <title>{@attribute}</title>
      <circle cx="16" cy="16" r="15" fill={@color} stroke="#1c1917" stroke-width="1.2" />
      <circle cx="16" cy="16" r="12.5" fill="none" stroke="#fff" stroke-opacity="0.45" />
      <text
        x="16"
        y="21.6"
        text-anchor="middle"
        font-size="15.5"
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

  @doc """
  A Pendulum Scale marker: blue on the left, red on the right, its outer
  corner reaching further out like on real cards.
  """
  attr :side, :string, required: true, values: ~w(left right)
  attr :class, :any, default: nil

  def scale_gem(assigns) do
    ~H"""
    <svg viewBox="0 0 12 10" class={@class} aria-hidden="true">
      <path
        d={if @side == "left", do: "M0 5 7 0.5 10 5 7 9.5z", else: "M12 5 5 0.5 2 5 5 9.5z"}
        fill={if @side == "left", do: "#2563eb", else: "#dc2626"}
      />
    </svg>
    """
  end

  @doc "One Level star (red-orange disc) or Rank star (black disc)."
  attr :rank, :boolean, default: false
  attr :class, :any, default: "mq-card__star"

  def level_star(assigns) do
    ~H"""
    <svg viewBox="0 0 32 32" class={@class} aria-hidden="true">
      <circle
        cx="16"
        cy="16"
        r="15"
        fill={if @rank, do: "#1c1917", else: "#d2461d"}
        stroke={if @rank, do: "#78716c", else: "#7c2d12"}
        stroke-width="1.5"
      />
      <polygon
        points="16,5 19.1,12.5 27,12.9 20.9,18 23,25.8 16,21.4 9,25.8 11.1,18 5,12.9 12.9,12.5"
        fill="#facc15"
        stroke="#713f12"
        stroke-width="0.8"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  @doc "A Spell/Trap property glyph: Quick-Play, Continuous, Equip, Field, Ritual or Counter."
  attr :property, :string, required: true
  attr :label, :string, default: nil, doc: "defaults to the property"
  attr :class, :any, default: nil

  def property_icon(assigns) do
    assigns = assign(assigns, :label, assigns.label || assigns.property)

    ~H"""
    <svg
      viewBox="0 0 24 24"
      class={@class}
      role="img"
      aria-label={@label}
      fill="none"
      stroke="currentColor"
      stroke-width="2.2"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <title>{@label}</title>
      <%= case @property do %>
        <% "Quick-Play" -> %>
          <path d="M13.5 2 4.5 13.5h6.5L9.5 22l10-12.5h-6.5z" fill="currentColor" stroke-width="1" />
        <% "Continuous" -> %>
          <path d="M6.5 8a4 4 0 1 0 0 8c2.6 0 3.6-2 5.5-4s2.9-4 5.5-4a4 4 0 1 1 0 8c-2.6 0-3.6-2-5.5-4s-2.9-4-5.5-4z" />
        <% "Equip" -> %>
          <path d="M12 3.5v17M3.5 12h17" stroke-width="3.4" />
        <% "Field" -> %>
          <%!-- a four-pointed star --%>
          <path
            d="M12 1.5 14.6 9.4 22.5 12 14.6 14.6 12 22.5 9.4 14.6 1.5 12 9.4 9.4z"
            fill="currentColor"
            stroke-width="1"
          />
        <% "Ritual" -> %>
          <%!-- a flame with three tongues, the middle one tallest --%>
          <path
            d="M12 22.5c-4.6 0-7.2-3-7.2-6.7 0-3 1.6-5 2.6-7.3.5 2.2 1.4 3.4 2.3 3.8-.3-3.2.9-6.8 2.3-10.3 1.4 3.5 2.6 7.1 2.3 10.3.9-.4 1.8-1.6 2.3-3.8 1 2.3 2.6 4.3 2.6 7.3 0 3.7-2.6 6.7-7.2 6.7z"
            fill="currentColor"
            stroke-width="1"
          />
        <% "Counter" -> %>
          <%!-- a quarter circle from 3 o'clock, clockwise to 6 o'clock --%>
          <path d="M20 5a14 14 0 0 1-14 14" stroke-width="2.6" />
          <path d="M2 19 8.2 14.6v8.8z" fill="currentColor" stroke-width="1" />
        <% _ -> %>
          <circle cx="12" cy="12" r="3" fill="currentColor" />
      <% end %>
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
