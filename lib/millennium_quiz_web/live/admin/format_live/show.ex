defmodule MillenniumQuizWeb.Admin.FormatLive.Show do
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.Quiz
  alias MillenniumQuiz.Quiz.{CardLinks, Question}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width="lg">
      <.link
        navigate={~p"/admin/formats"}
        class="text-sm text-base-content/60 hover:text-base-content"
      >
        <span aria-hidden="true">&larr;</span> Formats
      </.link>
      <.header>
        {@format.name}
        <:subtitle>
          <span class="inline-flex items-center gap-1" id="format-date">
            <.icon name="hero-calendar" class="size-4" /> {display_date(@format.date)}
          </span>
          <span :if={@format.description} class="block">{@format.description}</span>
        </:subtitle>
        <:actions>
          <div class="flex gap-2">
            <.button navigate={~p"/admin/formats/#{@format}/edit"} id="edit-format">
              <.icon name="hero-pencil-square" class="size-4" /> Edit
            </.button>
            <.button
              phx-click="confirm_delete"
              phx-value-what="format"
              class="btn btn-ghost text-error"
              id="delete-format"
              aria-label="Delete format"
            >
              <.icon name="hero-trash" class="size-4" />
            </.button>
          </div>
        </:actions>
      </.header>

      <p class="text-sm text-base-content/60">
        Questions are ordered from easiest to hardest. The easiest is worth 10 points by default,
        each following one 10 more. Set custom points on a question to override this.
      </p>

      <section
        :for={topic <- @format.topics}
        id={"topic-#{topic.id}"}
        class="rounded-box border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="flex items-center gap-3 border-b border-base-300 px-4 py-3">
          <h2 class="font-semibold flex-1">{topic.name}</h2>
          <span class="text-sm text-base-content/60">{length(topic.questions)} questions</span>
          <.link
            navigate={~p"/admin/topics/#{topic.id}/questions/new"}
            class="btn btn-sm btn-primary btn-soft"
            id={"add-question-#{topic.id}"}
          >
            <.icon name="hero-plus" class="size-4" /> Question
          </.link>
        </div>
        <ol class="divide-y divide-base-300">
          <li :if={topic.questions == []} class="px-4 py-6 text-center text-sm text-base-content/50">
            No questions yet.
          </li>
          <li
            :for={{q, i} <- Enum.with_index(topic.questions)}
            id={"question-#{q.id}"}
            class="flex items-center gap-3 px-4 py-2.5"
          >
            <span class="w-6 text-sm text-base-content/50 tabular-nums">{i + 1}.</span>
            <p class="flex-1 min-w-0 truncate">{CardLinks.plain(q.text)}</p>
            <span
              class={["badge badge-sm", if(q.points, do: "badge-secondary", else: "badge-ghost")]}
              title={if q.points, do: "Custom points", else: "Default points from position"}
            >
              {Question.effective_points(q)} {if q.points, do: "custom", else: "pts"}
            </span>
            <div class="join">
              <button
                class="btn btn-ghost btn-xs join-item"
                phx-click="move"
                phx-value-id={q.id}
                phx-value-dir="up"
                disabled={i == 0}
                id={"move-up-#{q.id}"}
                aria-label="Easier"
              >
                <.icon name="hero-chevron-up" class="size-4" />
              </button>
              <button
                class="btn btn-ghost btn-xs join-item"
                phx-click="move"
                phx-value-id={q.id}
                phx-value-dir="down"
                disabled={i == length(topic.questions) - 1}
                id={"move-down-#{q.id}"}
                aria-label="Harder"
              >
                <.icon name="hero-chevron-down" class="size-4" />
              </button>
            </div>
            <.link
              navigate={~p"/admin/questions/#{q.id}/edit"}
              class="btn btn-ghost btn-xs"
              id={"edit-question-#{q.id}"}
            >
              <.icon name="hero-pencil" class="size-4" />
            </.link>
            <button
              class="btn btn-ghost btn-xs text-error"
              phx-click="confirm_delete"
              phx-value-what="question"
              phx-value-id={q.id}
              id={"delete-question-#{q.id}"}
              aria-label="Delete question"
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </li>
        </ol>
      </section>

      <.confirm_dialog
        :if={@confirm && @confirm.what == :format}
        id="delete-format-dialog"
        title="Delete this format?"
        icon="hero-trash"
        on_cancel="cancel_confirm"
      >
        <p>
          <strong>{@format.name}</strong>
          will be deleted with all its topics and questions. This can't be undone.
        </p>
        <:actions>
          <button class="btn btn-ghost" phx-click="cancel_confirm" id="delete-format-dialog-cancel">
            Cancel
          </button>
          <button class="btn btn-error" phx-click="delete_format" id="delete-format-dialog-confirm">
            <.icon name="hero-trash" class="size-4" /> Delete format
          </button>
        </:actions>
      </.confirm_dialog>

      <.confirm_dialog
        :if={@confirm && @confirm.what == :question}
        id="delete-question-dialog"
        title="Delete this question?"
        icon="hero-trash"
        on_cancel="cancel_confirm"
      >
        <p>“{@confirm.label}”</p>
        <p class="mt-2 text-sm text-base-content/60">
          The questions after it move up one place. This can't be undone.
        </p>
        <:actions>
          <button
            class="btn btn-ghost"
            phx-click="cancel_confirm"
            id="delete-question-dialog-cancel"
          >
            Cancel
          </button>
          <button
            class="btn btn-error"
            phx-click="delete_question"
            phx-value-id={@confirm.id}
            id="delete-question-dialog-confirm"
          >
            <.icon name="hero-trash" class="size-4" /> Delete question
          </button>
        </:actions>
      </.confirm_dialog>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, socket |> assign(:confirm, nil) |> assign_format(id)}
  end

  @impl true
  def handle_event("move", %{"id" => id, "dir" => dir}, socket) when dir in ["up", "down"] do
    question = Quiz.get_question!(id)
    {:ok, _} = Quiz.move_question(question, String.to_existing_atom(dir))
    {:noreply, assign_format(socket, socket.assigns.format.id)}
  end

  # Deleting asks first, in an in-app dialog (see confirm_dialog/1).
  def handle_event("confirm_delete", %{"what" => "format"}, socket) do
    {:noreply, assign(socket, :confirm, %{what: :format})}
  end

  def handle_event("confirm_delete", %{"what" => "question", "id" => id}, socket) do
    case Quiz.get_question(id) do
      nil ->
        {:noreply, question_gone(socket)}

      question ->
        plain = CardLinks.plain(question.text)

        label =
          String.slice(plain, 0, 80) <> if(String.length(plain) > 80, do: "…", else: "")

        {:noreply, assign(socket, :confirm, %{what: :question, id: question.id, label: label})}
    end
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, assign(socket, :confirm, nil)}
  end

  def handle_event("delete_question", %{"id" => id}, socket) do
    case Quiz.get_question(id) do
      nil ->
        {:noreply, question_gone(socket)}

      question ->
        {:ok, _} = Quiz.delete_question(question)

        {:noreply,
         socket
         |> assign(:confirm, nil)
         |> put_flash(:info, "Question deleted.")
         |> assign_format(socket.assigns.format.id)}
    end
  end

  def handle_event("delete_format", _params, socket) do
    {:ok, _} = Quiz.delete_format(socket.assigns.format)

    {:noreply,
     socket
     |> put_flash(:info, "Format deleted.")
     |> push_navigate(to: ~p"/admin/formats")}
  end

  defp assign_format(socket, id) do
    format = Quiz.get_format!(id)

    socket
    |> assign(:page_title, format.name)
    |> assign(:format, format)
  end

  # E.g. deleted by another admin in the meantime: say so instead of crashing.
  defp question_gone(socket) do
    socket
    |> assign(:confirm, nil)
    |> put_flash(:error, "That question doesn't exist anymore.")
    |> assign_format(socket.assigns.format.id)
  end
end
