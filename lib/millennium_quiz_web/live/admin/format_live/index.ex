defmodule MillenniumQuizWeb.Admin.FormatLive.Index do
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.Quiz

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="lg">
      <.header>
        Formats
        <:subtitle>
          Each format has 2–6 topics; each topic has questions ordered by difficulty.
        </:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/admin/formats/new"} id="new-format">
            <.icon name="hero-plus" class="size-5" /> New format
          </.button>
        </:actions>
      </.header>

      <div id="formats" phx-update="stream" class="grid gap-3">
        <div class="hidden only:block rounded-box border border-dashed border-base-300 p-10 text-center text-base-content/60">
          No formats yet.
        </div>
        <.link
          :for={{dom_id, format} <- @streams.formats}
          id={dom_id}
          navigate={~p"/admin/formats/#{format}"}
          class="flex items-center gap-4 rounded-box border border-base-300 bg-base-100 p-4 transition hover:border-primary"
        >
          <div class="flex-1 min-w-0">
            <p class="font-semibold">
              {format.name}
              <span class="ml-1 text-sm font-normal text-base-content/60">
                {display_date(format.date)}
              </span>
            </p>
            <p class="text-sm text-base-content/60 truncate">
              {Enum.map_join(format.topics, " · ", &"#{&1.name} (#{length(&1.questions)})")}
            </p>
          </div>
          <.icon name="hero-chevron-right" class="size-5 text-base-content/40" />
        </.link>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Formats")
     |> stream(:formats, Quiz.list_formats())}
  end
end
