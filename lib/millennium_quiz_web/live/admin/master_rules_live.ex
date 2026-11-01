defmodule MillenniumQuizWeb.Admin.MasterRulesLive do
  @moduledoc """
  The Master Rules and the dates they start on. The dates are stored
  (`MillenniumQuiz.Quiz.MasterRules`) and read by the board validation and the
  board view. Only the dates are editable; what each rule has is shown.
  """
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.Quiz.MasterRules

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      pending_submissions={@pending_submissions}
    >
      <div class="duel-admin space-y-6">
        <.header>
          Master Rules
          <:subtitle>
            The board of a question follows the Master Rule in force on the date of its format.
            Check these dates when you find one is wrong; they are from memory.
          </:subtitle>
        </.header>

        <.form
          for={%{}}
          id="master-rules-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6"
        >
          <ul class="space-y-3" id="master-rules">
            <li
              :for={rule <- @rules}
              id={"rule-#{rule.key}"}
              class="duel-plate duel-panel rounded-box border border-base-300 bg-base-100 p-5 space-y-3"
            >
              <h2 class="font-semibold">{rule.name}</h2>
              <p :if={rule.starts_on == nil} class="text-sm" id={"rule-#{rule.key}-start"}>
                In force from the beginning, until Master Rule 3 starts.
              </p>
              <.input
                :if={rule.starts_on != nil}
                id={"rules_#{rule.key}"}
                name={"rules[#{rule.key}]"}
                type="date"
                label="Starts on"
                value={@values[rule.key]}
                errors={@errors[rule.key] || []}
                required
              />
              <p class="text-sm text-base-content/70" id={"rule-#{rule.key}-has"}>
                <.has label="Extra Monster Zones" on={rule.emz} />
                <.has label="Pendulum scales" on={rule.pendulum_scales} />
              </p>
            </li>
          </ul>

          <section
            id="feature-xyz"
            class="duel-plate duel-panel rounded-box border border-base-300 bg-base-100 p-5 space-y-3"
          >
            <h2 class="font-semibold">Overlay units (Xyz Monsters)</h2>
            <.input
              id="rules_xyz"
              name="rules[xyz]"
              type="date"
              label="Exist from"
              value={@values[:xyz]}
              errors={@errors[:xyz] || []}
              required
            />
            <p class="text-sm text-base-content/70">
              Xyz Monsters came out in the middle of the first era, so this date belongs to no
              Master Rule. A board of an earlier format cannot have overlay units.
            </p>
          </section>

          <section
            class="duel-plate duel-panel rounded-box border border-base-300 bg-base-100 p-5 space-y-2 text-sm text-base-content/80"
            id="master-rules-note"
          >
            <h2 class="font-semibold text-base">What a change does</h2>
            <ul class="list-disc space-y-1 pl-5">
              <li>
                A saved question keeps its board, and a running or paused game keeps the rule
                that was copied into it when the game began. Nothing is rewritten.
              </li>
              <li>
                A question whose board no longer fits the new dates shows a warning the next
                time it is edited.
              </li>
              <li>
                The Master Rule 1/2 era has no start date: it lasts until Master Rule 3 starts,
                and each rule lasts until the next one starts, so there are no gaps and no
                overlaps.
              </li>
              <li>The dates are part of the backup.</li>
            </ul>
          </section>

          <div class="flex flex-wrap gap-2">
            <.button variant="primary" id="save-master-rules" phx-disable-with="Saving…">
              <.icon name="hero-check" class="size-5" /> Save
            </.button>
            <button type="button" class="btn" phx-click="ask_reset" id="reset-master-rules">
              <.icon name="hero-arrow-uturn-left" class="size-5" /> Reset to defaults
            </button>
          </div>
        </.form>

        <.confirm_dialog
          :if={@confirm}
          id="reset-dialog"
          title="Reset the Master Rules?"
          icon="hero-arrow-uturn-left"
          on_cancel="cancel"
        >
          <p>
            Master Rule 3 starts on {@defaults.mr3}, Master Rule 4 on {@defaults.mr4} and Xyz
            Monsters exist from {@defaults.xyz}. Saved questions and games keep their boards.
          </p>
          <:actions>
            <button class="btn btn-ghost" phx-click="cancel" id="reset-dialog-cancel">Cancel</button>
            <button class="btn btn-primary" phx-click="reset" id="reset-dialog-confirm">
              <.icon name="hero-arrow-uturn-left" class="size-4" /> Reset
            </button>
          </:actions>
        </.confirm_dialog>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :on, :boolean, required: true

  defp has(assigns) do
    ~H"""
    <span class="mr-3 inline-flex items-center gap-1 whitespace-nowrap max-sm:mr-0 max-sm:flex">
      <.icon name={if @on, do: "hero-check-circle", else: "hero-x-circle"} class="size-4" />
      {@label}: {if @on, do: "yes", else: "no"}
    </span>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Master Rules")
     |> assign(:defaults, MasterRules.default_dates())
     |> assign(:confirm, false)
     |> load()}
  end

  # What is stored, shown fresh (no errors).
  defp load(socket) do
    {rules, _features} = MasterRules.current()

    socket
    |> assign(:rules, rules)
    |> assign(:values, MasterRules.dates())
    |> assign(:errors, %{})
  end

  @impl true
  def handle_event("validate", %{"rules" => params}, socket) do
    {:noreply, show_errors(socket, params)}
  end

  def handle_event("save", %{"rules" => params}, socket) do
    case MasterRules.save(params) do
      {:ok, _dates} ->
        {:noreply, socket |> load() |> put_flash(:info, "Master Rules saved.")}

      {:error, _errors} ->
        {:noreply, show_errors(socket, params)}
    end
  end

  def handle_event("ask_reset", _params, socket), do: {:noreply, assign(socket, :confirm, true)}
  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, :confirm, false)}

  def handle_event("reset", _params, socket) do
    {:ok, _} = MasterRules.reset()

    {:noreply,
     socket
     |> assign(:confirm, false)
     |> load()
     |> put_flash(:info, "Master Rules reset to the defaults.")}
  end

  # Keeps what was typed and shows what is wrong with it.
  defp show_errors(socket, params) do
    errors =
      case MasterRules.validate(params) do
        {:ok, _} -> %{}
        {:error, errors} -> Map.new(errors, fn {k, v} -> {k, [v]} end)
      end

    values =
      Map.new([:mr3, :mr4, :xyz], fn k -> {k, params[Atom.to_string(k)]} end)

    socket |> assign(:values, values) |> assign(:errors, errors)
  end
end
