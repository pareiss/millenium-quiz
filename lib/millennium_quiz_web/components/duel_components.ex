defmodule MillenniumQuizWeb.DuelComponents do
  @moduledoc """
  Building blocks of the opt-in "duel" look (5D's / Neo Domino): the life point
  gauge, the ATK label, the Synchro ring and the question progress rail.

  Their CSS is in `assets/css/app.css` and applies only under the daisyUI themes
  `duel-dark` and `duel-light`; under the other themes the markup is unstyled but
  still readable (names, numbers and status are real text). They are not used on
  the game screens yet.
  """
  use Phoenix.Component

  import MillenniumQuizWeb.CoreComponents, only: [avatar: 1]

  @doc """
  A player's life point gauge: avatar, name, the LP number on a plate (with
  leading zeros), a depleting bar and, after a hit, a ghost of the lost part.

  One markup for every width: the wrapper is a container, and the CSS rearranges
  it at 420px and wider (wide), 200 to 419px (compact), below 200px (mini) and below
  100px (tight: number and bar only, the name stays for screen readers).

  The state is never shown by colour alone: a hit shows its damage as text, an
  eliminated player shows "K.O." and a grey, empty bar, the active player has a
  Synchro ring around the avatar and `aria-current`.
  """
  attr :id, :string, default: nil
  attr :name, :string, required: true
  attr :avatar, :string, default: nil, doc: "the avatar slug"
  attr :crop, :map, default: nil, doc: "the avatar's crop, see `CoreComponents.avatar/1`"
  attr :lp, :integer, required: true
  attr :start_lp, :integer, required: true
  attr :player, :integer, default: 0, doc: "0..3, picks the colour --duel-p1..p4"
  attr :status, :atom, default: :alive, values: [:alive, :hit, :eliminated]
  attr :damage, :integer, default: nil, doc: "the amount just lost (the ghost segment)"
  attr :active, :boolean, default: false, doc: "the current chooser or answerer"
  attr :class, :any, default: nil

  def lp_gauge(assigns) do
    lp = max(assigns.lp, 0)
    start = max(assigns.start_lp, 1)
    # 0 LP is K.O., whatever the caller passed (a player knocked out by this
    # very hit arrives as :hit); the ghost still shows the final hit
    status = if lp == 0, do: :eliminated, else: assigns.status
    damage = if assigns.damage && assigns.damage > 0, do: assigns.damage, else: nil
    # a living player always shows a sliver of bar
    lp_pct = if lp > 0, do: max(pct(lp, start), 3.0), else: 0.0

    assigns =
      assigns
      |> assign(:status, status)
      |> assign(:player, assigns.player |> max(0) |> min(3))
      |> assign(:number, number(lp, start))
      |> assign(:lp_value, lp)
      |> assign(:lp_pct, lp_pct)
      |> assign(:damage, damage)
      |> assign(:ghost_pct, damage && min(pct(damage, start), 100 - lp_pct))

    ~H"""
    <div
      id={@id}
      class={["duel-gauge", @class]}
      data-player={@player + 1}
      data-status={@status}
      data-active={to_string(@active)}
    >
      <div class="duel-gauge-body" aria-current={@active && "true"}>
        <div class="duel-gauge-avatar">
          <.synchro_ring :if={@active} class="size-full">
            <.avatar slug={@avatar} crop={@crop} title={@name} class="size-full !ring-0" />
          </.synchro_ring>
          <span :if={!@active} class="duel-gauge-avatar-plain">
            <.avatar slug={@avatar} crop={@crop} title={@name} class="size-full !ring-0" />
          </span>
        </div>
        <span class="duel-gauge-name" title={@name}>{@name}</span>
        <div class="duel-gauge-plate">
          <span class="duel-gauge-lp-label" aria-hidden="true">LP</span>
          <span class="duel-gauge-num"><span :if={@number.zeros != ""} class="duel-gauge-zeros">{@number.zeros}</span>{@number.digits}</span>
          <span :if={@status == :eliminated} class="duel-gauge-ko">
            <span aria-hidden="true">✕</span> K.O.
          </span>
          <span :if={@status == :hit and @damage} class="duel-gauge-dmg">
            <span aria-hidden="true">▼</span> −{@damage}
          </span>
          <span :if={@status == :hit and !@damage} class="duel-gauge-dmg">
            <span aria-hidden="true">▼</span> HIT
          </span>
        </div>
        <div class="duel-gauge-bar" aria-hidden="true">
          <div class="duel-gauge-fill" style={"width:#{@lp_pct}%"}></div>
          <div
            :if={@ghost_pct && @ghost_pct > 0}
            class="duel-gauge-ghost"
            style={"left:#{@lp_pct}%;width:#{@ghost_pct}%"}
          >
          </div>
        </div>
      </div>
    </div>
    """
  end

  # 0..100, one decimal
  defp pct(value, total), do: min(Float.round(value * 100 / total, 1), 100.0)

  # "04000": at least 5 digits, or the digits of the start LP if more
  defp number(lp, start) do
    width = max(5, start |> Integer.to_string() |> String.length())
    text = lp |> Integer.to_string() |> String.pad_leading(width, "0")
    digits = Integer.to_string(lp)
    zeros = String.slice(text, 0, String.length(text) - String.length(digits))
    %{zeros: zeros, digits: digits}
  end

  @doc """
  The red "ATK" pill, optionally in front of a value (a damage number).

  ## Examples

      <.atk_label value="1600" />
  """
  attr :value, :any, default: nil
  attr :class, :any, default: nil

  def atk_label(assigns) do
    ~H"""
    <span class={["duel-atk", @class]}>
      <span class="duel-atk-pill">ATK</span>
      <span :if={@value != nil} class="duel-atk-value">{@value}</span>
    </span>
    """
  end

  @doc """
  The Synchro ring: 12 identical dashes around its content (an avatar), the
  turn marker. The ring shape is the `<symbol id="duel-ring">` of the root layout.
  The ring sizes with its parent: give it a class like `size-14`.
  """
  attr :class, :any, default: "size-14"
  slot :inner_block

  def synchro_ring(assigns) do
    ~H"""
    <span class={["duel-ring relative inline-block shrink-0", @class]}>
      <svg
        viewBox="0 0 64 64"
        class="duel-ring-svg absolute inset-0 size-full overflow-visible"
        aria-hidden="true"
        focusable="false"
      >
        <use href="#duel-ring" />
      </svg>
      <span class="duel-ring-inner absolute inset-[13%] overflow-hidden rounded-full">
        {render_slot(@inner_block)}
      </span>
    </span>
    """
  end

  @doc """
  The question progress rail: `total` slanted blocks, the answered ones filled,
  the current one a glowing orb, the rest dim. The blocks are decorative; the
  rail is a progress bar with a text value for screen readers.
  """
  attr :id, :string, default: nil
  attr :total, :integer, required: true
  attr :current, :integer, required: true, doc: "1-based number of the current question"
  attr :label, :string, default: "Question"
  attr :class, :any, default: nil

  def orb_rail(assigns) do
    total = max(assigns.total, 1)
    current = assigns.current |> max(1) |> min(total)
    assigns = assigns |> assign(:total, total) |> assign(:current, current)

    ~H"""
    <div
      id={@id}
      class={["duel-rail", @class]}
      role="progressbar"
      aria-valuemin="1"
      aria-valuemax={@total}
      aria-valuenow={@current}
      aria-valuetext={"#{@label} #{@current} of #{@total}"}
      aria-label={@label}
    >
      <span
        :for={n <- 1..@total}
        class="duel-rail-block"
        data-state={block_state(n, @current)}
        aria-hidden="true"
      ></span>
    </div>
    """
  end

  defp block_state(n, current) when n < current, do: "answered"
  defp block_state(n, current) when n == current, do: "current"
  defp block_state(_n, _current), do: "upcoming"
end
