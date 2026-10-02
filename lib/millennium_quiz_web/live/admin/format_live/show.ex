defmodule MillenniumQuizWeb.Admin.FormatLive.Show do
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.Quiz
  alias MillenniumQuiz.Quiz.Question

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
              phx-click="delete_format"
              data-confirm="Delete this format with all topics and questions?"
              class="btn btn-ghost text-error"
              id="delete-format"
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
            <p class="flex-1 min-w-0 truncate">{q.text}</p>
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
              phx-click="delete_question"
              phx-value-id={q.id}
              data-confirm="Delete this question?"
              id={"delete-question-#{q.id}"}
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </li>
        </ol>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, assign_format(socket, id)}
  end

  @impl true
  def handle_event("move", %{"id" => id, "dir" => dir}, socket) when dir in ["up", "down"] do
    question = Quiz.get_question!(id)
    {:ok, _} = Quiz.move_question(question, String.to_existing_atom(dir))
    {:noreply, assign_format(socket, socket.assigns.format.id)}
  end

  def handle_event("delete_question", %{"id" => id}, socket) do
    {:ok, _} = id |> Quiz.get_question!() |> Quiz.delete_question()
    {:noreply, assign_format(socket, socket.assigns.format.id)}
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
end
