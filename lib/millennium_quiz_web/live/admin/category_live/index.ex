defmodule MillenniumQuizWeb.Admin.CategoryLive.Index do
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.Quiz

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="lg">
      <.header>
        Categories
        <:subtitle>
          Each category has 2–6 topics; each topic has questions ordered by difficulty.
        </:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/admin/categories/new"} id="new-category">
            <.icon name="hero-plus" class="size-5" /> New category
          </.button>
        </:actions>
      </.header>

      <div id="categories" phx-update="stream" class="grid gap-3">
        <div class="hidden only:block rounded-box border border-dashed border-base-300 p-10 text-center text-base-content/60">
          No categories yet.
        </div>
        <.link
          :for={{dom_id, category} <- @streams.categories}
          id={dom_id}
          navigate={~p"/admin/categories/#{category}"}
          class="flex items-center gap-4 rounded-box border border-base-300 bg-base-100 p-4 transition hover:border-primary"
        >
          <div class="flex-1 min-w-0">
            <p class="font-semibold">{category.name}</p>
            <p class="text-sm text-base-content/60 truncate">
              {Enum.map_join(category.topics, " · ", &"#{&1.name} (#{length(&1.questions)})")}
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
     |> assign(:page_title, "Categories")
     |> stream(:categories, Quiz.list_categories())}
  end
end
