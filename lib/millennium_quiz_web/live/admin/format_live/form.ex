defmodule MillenniumQuizWeb.Admin.FormatLive.Form do
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.Quiz
  alias MillenniumQuiz.Quiz.Format

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

      <.form for={@form} id="format-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <.input field={@form[:name]} label="Name" maxlength="80" />
        <%= if @format.id do %>
          <div class="fieldset mb-2" id="format-date">
            <span class="label mb-1">Date</span>
            <p class="font-medium">{display_date(@format.date)}</p>
          </div>
          <p class="-mt-2 text-sm text-base-content/60">
            The date is fixed once a format exists: the cards on its questions were chosen
            for it.
          </p>
        <% else %>
          <.input field={@form[:date]} type="date" label="Date" />
          <p class="-mt-2 text-sm text-base-content/60">
            The point in time this format represents: only cards released by then can be used,
            and card texts show the errata that applied on this date. It can't be changed later.
          </p>
        <% end %>
        <.input field={@form[:description]} type="textarea" label="Description" rows="2" />

        <fieldset class="space-y-2">
          <legend class="font-medium mb-1">
            Topics
            <span class="text-sm text-base-content/60">({Format.min_topics()}–{Format.max_topics()})</span>
          </legend>
          <.inputs_for :let={topic} field={@form[:topics]}>
            <div class="flex items-start gap-2">
              <input type="hidden" name="format[topics_sort][]" value={topic.index} />
              <span class="mt-2 grid place-items-center size-8 shrink-0 rounded-full bg-base-200 text-sm">
                {topic.index + 1}
              </span>
              <div class="flex-1">
                <.input field={topic[:name]} placeholder="Topic name" maxlength="80" />
              </div>
              <button
                type="button"
                name="format[topics_drop][]"
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
          <input type="hidden" name="format[topics_drop][]" />
          <p :for={msg <- topic_errors(@form)} class="text-sm text-error flex gap-2 items-center">
            <.icon name="hero-exclamation-circle" class="size-5" /> {msg}
          </p>
          <button
            :if={topic_count(@form) < Format.max_topics()}
            type="button"
            name="format[topics_sort][]"
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
          <.button variant="primary" phx-disable-with="Saving…" id="save-format">Save</.button>
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
    format = %Format{topics: []}
    # Start with two empty topic rows (as params, so they have no duplicate nil ids).
    two_topics = %{"topics" => %{"0" => %{"name" => ""}, "1" => %{"name" => ""}}}

    socket
    |> assign(:page_title, "New format")
    |> assign(:format, format)
    |> assign(:return_to, ~p"/admin/formats")
    |> assign(:form, to_form(Quiz.change_format(format, two_topics)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    format = Quiz.get_format!(id)

    socket
    |> assign(:page_title, "Edit #{format.name}")
    |> assign(:format, format)
    |> assign(:return_to, ~p"/admin/formats/#{format}")
    |> assign(:form, to_form(Quiz.change_format(format)))
  end

  @impl true
  def handle_event("validate", %{"format" => params}, socket) do
    changeset = Quiz.change_format(socket.assigns.format, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"format" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  defp save(socket, :new, params) do
    case Quiz.create_format(params) do
      {:ok, format} ->
        {:noreply,
         socket
         |> put_flash(:info, "Format created. Now add questions to its topics.")
         |> push_navigate(to: ~p"/admin/formats/#{format}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save(socket, :edit, params) do
    case Quiz.update_format(socket.assigns.format, params) do
      {:ok, format} ->
        {:noreply,
         socket
         |> put_flash(:info, "Format updated.")
         |> push_navigate(to: ~p"/admin/formats/#{format}")}

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
