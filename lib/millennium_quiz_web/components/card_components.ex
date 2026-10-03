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
  """
  attr :card, :map, required: true
  attr :size, :string, default: "small", values: ~w(small large)
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
          [{kind(@card)} Card<.property_icon
            :if={@card[:property] not in [nil, "Normal"]}
            property={@card.property}
            class="mq-card__property"
          />]
        </div>
        <div
          :if={not @spell_trap? and not @link?}
          class={["mq-card__stars", @card[:rank] && "mq-card__stars--rank"]}
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

        <div :if={@pendulum?} class="mq-card__pendulum">
          <span class="mq-card__scale mq-card__scale--left" title="Pendulum Scale">
            {@card[:pendulum_scale]}
          </span>
          <p class="mq-card__pendulum-text">{@card[:pendulum_text]}</p>
          <span class="mq-card__scale mq-card__scale--right" title="Pendulum Scale">
            {@card[:pendulum_scale]}
          </span>
        </div>

        <div class="mq-card__text">
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
    """
  end

  @doc """
  A card enlarged in a dialog. Esc, the backdrop and the close button send
  `on_close`.
  """
  attr :id, :string, required: true
  attr :card, :map, required: true
  attr :on_close, :string, required: true
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
        <.card card={@card} size="large" class="w-full" />
        <p :if={@card.set} class="text-sm text-white/90">As printed in {@card.set}</p>
        {render_slot(@inner_block)}
      </div>
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

  @doc "One Level star (red-orange disc) or Rank star (black disc)."
  attr :rank, :boolean, default: false

  def level_star(assigns) do
    ~H"""
    <svg viewBox="0 0 32 32" class="mq-card__star" aria-hidden="true">
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
  attr :class, :any, default: nil

  def property_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      class={@class}
      role="img"
      aria-label={@property}
      fill="none"
      stroke="currentColor"
      stroke-width="2.2"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <title>{@property}</title>
      <%= case @property do %>
        <% "Quick-Play" -> %>
          <path d="M13.5 2 4.5 13.5h6.5L9.5 22l10-12.5h-6.5z" fill="currentColor" stroke-width="1" />
        <% "Continuous" -> %>
          <path d="M6.5 8a4 4 0 1 0 0 8c2.6 0 3.6-2 5.5-4s2.9-4 5.5-4a4 4 0 1 1 0 8c-2.6 0-3.6-2-5.5-4s-2.9-4-5.5-4z" />
        <% "Equip" -> %>
          <path d="M12 3.5v17M3.5 12h17" stroke-width="3.4" />
        <% "Field" -> %>
          <circle cx="12" cy="12" r="8.5" />
          <path d="M12 4.5 14.2 12 12 19.5 9.8 12z" fill="currentColor" stroke-width="1" />
        <% "Ritual" -> %>
          <path
            d="M12 2.5c.8 3.8 6 6 6 11.5a6 6 0 0 1-12 0c0-3 1.8-5 3-6.8.2 2 1 3.2 2.2 3.4C11 8 11 5.2 12 2.5z"
            fill="currentColor"
            stroke-width="1"
          />
        <% "Counter" -> %>
          <path d="M18.5 14.5a6.5 6.5 0 1 1-2-7.2" /><path d="M17.5 3v5h-5" />
        <% _ -> %>
          <circle cx="12" cy="12" r="3" fill="currentColor" />
      <% end %>
    </svg>
    """
  end

  ## Helpers

  defp link_arrows, do: @link_arrows

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
