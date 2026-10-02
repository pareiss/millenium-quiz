defmodule MillenniumQuizWeb.Admin.QuestionLive.Form do
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.Quiz
  alias MillenniumQuiz.Quiz.{Choice, Question}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.link navigate={@return_to} class="text-sm text-base-content/60 hover:text-base-content">
        <span aria-hidden="true">&larr;</span> {@topic.category.name}
      </.link>
      <.header>
        {@page_title}
        <:subtitle>Topic: {@topic.name}</:subtitle>
      </.header>

      <.form for={@form} id="question-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <.input field={@form[:text]} type="textarea" label="Question" rows="3" maxlength="1000" />

        <.input
          field={@form[:points]}
          type="number"
          label="Points"
          min="1"
          placeholder={"#{@default_points} (default for position #{@question.position + 1})"}
        />

        <fieldset class="space-y-2">
          <legend class="font-medium mb-1">
            Answers <span class="text-sm text-base-content/60">(2–6, tick the correct one)</span>
          </legend>
          <.inputs_for :let={choice} field={@form[:choices]}>
            <div class="flex items-start gap-2">
              <input type="hidden" name="question[choices_sort][]" value={choice.index} />
              <span class="mt-2 grid place-items-center size-8 shrink-0 rounded-full bg-base-200 text-sm font-semibold">
                {<<?A + choice.index>>}
              </span>
              <div class="flex-1">
                <.input field={choice[:text]} placeholder="Answer" maxlength="200" />
              </div>
              <div class="mt-2">
                <.input
                  field={choice[:correct]}
                  type="checkbox"
                  label="Correct"
                  class="checkbox checkbox-success checkbox-sm mr-1"
                />
              </div>
              <button
                type="button"
                name="question[choices_drop][]"
                value={choice.index}
                phx-click={JS.dispatch("change")}
                class="btn btn-ghost btn-square mt-0.5"
                id={"remove-choice-#{choice.index}"}
                aria-label="Remove answer"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>
          </.inputs_for>
          <input type="hidden" name="question[choices_drop][]" />
          <p
            :for={msg <- choice_errors(@form)}
            class="text-sm text-error flex gap-2 items-center"
            id="choice-errors"
          >
            <.icon name="hero-exclamation-circle" class="size-5" /> {msg}
          </p>
          <button
            type="button"
            name="question[choices_sort][]"
            value="new"
            phx-click={JS.dispatch("change")}
            class="btn btn-ghost btn-sm"
            id="add-choice"
          >
            <.icon name="hero-plus" class="size-4" /> Add answer
          </button>
        </fieldset>

        <div class="flex gap-2 pt-2">
          <.button variant="primary" phx-disable-with="Saving…" id="save-question">Save</.button>
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

  defp apply_action(socket, :new, %{"topic_id" => topic_id}) do
    topic = Quiz.get_topic!(topic_id)

    question = %Question{
      topic_id: topic.id,
      position: Quiz.next_question_position(topic),
      choices: List.duplicate(%Choice{}, 4)
    }

    socket
    |> assign(:page_title, "New question")
    |> assign_form(topic, question)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    question = Quiz.get_question!(id)
    topic = Quiz.get_topic!(question.topic_id)

    socket
    |> assign(:page_title, "Edit question")
    |> assign_form(topic, question)
  end

  defp assign_form(socket, topic, question) do
    socket
    |> assign(:topic, topic)
    |> assign(:question, question)
    |> assign(:default_points, Question.default_points(question.position))
    |> assign(:return_to, ~p"/admin/categories/#{topic.category_id}")
    |> assign(:form, to_form(Quiz.change_question(question)))
  end

  @impl true
  def handle_event("validate", %{"question" => params}, socket) do
    changeset = Quiz.change_question(socket.assigns.question, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"question" => params}, socket) do
    result =
      case socket.assigns.live_action do
        :new -> Quiz.create_question(socket.assigns.topic, params)
        :edit -> Quiz.update_question(socket.assigns.question, params)
      end

    case result do
      {:ok, _question} ->
        {:noreply,
         socket
         |> put_flash(:info, "Question saved.")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp choice_errors(form) do
    if form.source.action do
      for {msg, opts} <- Keyword.get_values(form.source.errors, :choices),
          do: translate_error({msg, opts})
    else
      []
    end
  end
end
