defmodule MillenniumQuizWeb.Admin.CategoryLive.Form do
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.Quiz
  alias MillenniumQuiz.Quiz.Category

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>
          Topics define the kinds of questions, e.g. "Monsters", "Spells", "History".
        </:subtitle>
      </.header>

      <.form for={@form} id="category-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <.input field={@form[:name]} label="Name" maxlength="80" />
        <.input field={@form[:description]} type="textarea" label="Description" rows="2" />

        <fieldset class="space-y-2">
          <legend class="font-medium mb-1">
            Topics
            <span class="text-sm text-base-content/60">({Category.min_topics()}–{Category.max_topics()})</span>
          </legend>
          <.inputs_for :let={topic} field={@form[:topics]}>
            <div class="flex items-start gap-2">
              <input type="hidden" name="category[topics_sort][]" value={topic.index} />
              <span class="mt-2 grid place-items-center size-8 shrink-0 rounded-full bg-base-200 text-sm">
                {topic.index + 1}
              </span>
              <div class="flex-1">
                <.input field={topic[:name]} placeholder="Topic name" maxlength="80" />
              </div>
              <button
                type="button"
                name="category[topics_drop][]"
                value={topic.index}
                phx-click={JS.dispatch("change")}
                class="btn btn-ghost btn-square mt-0.5"
                id={"remove-topic-#{topic.index}"}
                aria-label="Remove topic"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>
          </.inputs_for>
          <input type="hidden" name="category[topics_drop][]" />
          <p :for={msg <- topic_errors(@form)} class="text-sm text-error flex gap-2 items-center">
            <.icon name="hero-exclamation-circle" class="size-5" /> {msg}
          </p>
          <button
            :if={topic_count(@form) < Category.max_topics()}
            type="button"
            name="category[topics_sort][]"
            value="new"
            phx-click={JS.dispatch("change")}
            class="btn btn-ghost btn-sm"
            id="add-topic"
          >
            <.icon name="hero-plus" class="size-4" /> Add topic
          </button>
          <p :if={@live_action == :edit} class="text-xs text-base-content/60">
            Removing a topic also deletes its questions.
          </p>
        </fieldset>

        <div class="flex gap-2 pt-2">
          <.button variant="primary" phx-disable-with="Saving…" id="save-category">Save</.button>
          <.button navigate={@return_to}>Cancel</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    category = %Category{topics: []}
    # Start with two empty topic rows (as params, so they have no duplicate nil ids).
    two_topics = %{"topics" => %{"0" => %{"name" => ""}, "1" => %{"name" => ""}}}

    socket
    |> assign(:page_title, "New category")
    |> assign(:category, category)
    |> assign(:return_to, ~p"/admin/categories")
    |> assign(:form, to_form(Quiz.change_category(category, two_topics)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    category = Quiz.get_category!(id)

    socket
    |> assign(:page_title, "Edit #{category.name}")
    |> assign(:category, category)
    |> assign(:return_to, ~p"/admin/categories/#{category}")
    |> assign(:form, to_form(Quiz.change_category(category)))
  end

  @impl true
  def handle_event("validate", %{"category" => params}, socket) do
    changeset = Quiz.change_category(socket.assigns.category, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"category" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  defp save(socket, :new, params) do
    case Quiz.create_category(params) do
      {:ok, category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category created. Now add questions to its topics.")
         |> push_navigate(to: ~p"/admin/categories/#{category}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save(socket, :edit, params) do
    case Quiz.update_category(socket.assigns.category, params) do
      {:ok, category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category updated.")
         |> push_navigate(to: ~p"/admin/categories/#{category}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp topic_count(form) do
    form.source |> Ecto.Changeset.get_assoc(:topics, :struct) |> length()
  end

  defp topic_errors(form) do
    if form.source.action do
      for {msg, opts} <- Keyword.get_values(form.source.errors, :topics),
          do: translate_error({msg, opts})
    else
      []
    end
  end
end
