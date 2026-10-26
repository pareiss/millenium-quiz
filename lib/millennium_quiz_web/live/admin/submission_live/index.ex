defmodule MillenniumQuizWeb.Admin.SubmissionLive.Index do
  @moduledoc """
  The review queue of questions suggested by players. Approving opens the
  question form prefilled (`QuestionLive.Form`); the submission itself is never
  edited.
  """
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.Quiz

  @filters ~w(pending approved rejected all)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      pending_submissions={@pending_submissions}
    >
      <.header>
        Suggested questions
        <:subtitle>Questions sent in by players, waiting for you to add, edit or reject.</:subtitle>
      </.header>

      <div role="tablist" class="tabs tabs-border" id="submission-filters">
        <.link
          :for={f <- filters()}
          patch={~p"/admin/submissions?#{[status: f]}"}
          role="tab"
          id={"filter-#{f}"}
          class={["tab", f == @filter && "tab-active"]}
        >
          {String.capitalize(f)}
          <span :if={f == "pending"} class="badge badge-sm badge-primary ml-1" id="pending-count">
            {@pending_count}
          </span>
        </.link>
      </div>

      <p
        :if={@submissions == []}
        class="rounded-box border border-dashed border-base-300 p-8 text-center text-base-content/60"
        id="no-submissions"
      >
        Nothing here.
      </p>

      <ul class="space-y-3" id="submissions">
        <li
          :for={s <- @submissions}
          id={"submission-#{s.id}"}
          class="rounded-box border border-base-300 bg-base-100 p-4 space-y-2"
        >
          <div class="flex flex-wrap items-center gap-2 text-sm text-base-content/60">
            <span>{s.topic.format.name} · {s.topic.name}</span>
            <span class={["badge badge-sm", status_class(s.status)]}>{s.status}</span>
            <span>
              {if s.submitter_name, do: "by #{s.submitter_name}", else: "no name"} · {Calendar.strftime(
                s.inserted_at,
                "%Y-%m-%d %H:%M"
              )}
            </span>
          </div>
          <p class="font-semibold whitespace-pre-line">{s.text}</p>
          <ol class="list-[upper-alpha] pl-6 text-sm">
            <li :for={c <- s.choices} class={c.correct && "font-semibold"}>{c.text}</li>
          </ol>
          <div class="flex flex-wrap gap-2 pt-1">
            <.button
              :if={s.status == "pending"}
              variant="primary"
              navigate={~p"/admin/topics/#{s.topic_id}/questions/new?#{[submission: s.id]}"}
              id={"review-#{s.id}"}
            >
              Review and add
            </.button>
            <button
              :if={s.status == "pending"}
              class="btn btn-ghost"
              phx-click="confirm"
              phx-value-what="reject"
              phx-value-id={s.id}
              id={"reject-#{s.id}"}
            >
              Reject
            </button>
            <.button
              :if={s.status == "approved" and s.question_id}
              navigate={~p"/admin/questions/#{s.question_id}/edit"}
              id={"question-#{s.id}"}
            >
              Open the question
            </.button>
            <button
              :if={s.status != "pending"}
              class="btn btn-ghost"
              phx-click="confirm"
              phx-value-what="delete"
              phx-value-id={s.id}
              id={"delete-#{s.id}"}
            >
              Delete
            </button>
          </div>
        </li>
      </ul>

      <.confirm_dialog
        :if={@confirm}
        id="submission-dialog"
        title={
          if @confirm.what == :reject, do: "Reject this suggestion?", else: "Delete this suggestion?"
        }
        on_cancel="cancel"
        cancel_id="submission-dialog-cancel"
      >
        <p :if={@confirm.what == :reject}>
          It is kept under "Rejected". The player sees on their page that it was not added.
        </p>
        <p :if={@confirm.what == :delete}>
          The suggestion is removed for good. A question made from it stays.
        </p>
        <:actions>
          <button class="btn btn-ghost" phx-click="cancel" id="submission-dialog-cancel">
            Cancel
          </button>
          <button class="btn btn-error" phx-click="do_confirm" id="submission-dialog-confirm">
            {if @confirm.what == :reject, do: "Reject", else: "Delete"}
          </button>
        </:actions>
      </.confirm_dialog>
    </Layouts.app>
    """
  end

  def filters, do: @filters

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Suggested questions", confirm: nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter = if params["status"] in @filters, do: params["status"], else: "pending"
    {:noreply, socket |> assign(:filter, filter) |> load()}
  end

  @impl true
  def handle_event("confirm", %{"what" => what, "id" => id}, socket)
      when what in ~w(reject delete) do
    case Quiz.get_submission(id) do
      nil -> {:noreply, load(socket)}
      s -> {:noreply, assign(socket, :confirm, %{what: String.to_existing_atom(what), id: s.id})}
    end
  end

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, :confirm, nil)}

  def handle_event("do_confirm", _params, %{assigns: %{confirm: %{what: what, id: id}}} = socket) do
    socket =
      with %{} = s <- Quiz.get_submission(id) do
        case {what, apply_review(what, s)} do
          {:reject, :ok} -> put_flash(socket, :info, "Suggestion rejected.")
          {:delete, {:ok, _}} -> put_flash(socket, :info, "Suggestion deleted.")
          _ -> put_flash(socket, :error, "That suggestion was already reviewed.")
        end
      else
        _ -> socket
      end

    {:noreply, socket |> assign(:confirm, nil) |> load()}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # A pending suggestion is never deleted, only rejected first.
  defp apply_review(:reject, s), do: Quiz.reject_submission(s)
  defp apply_review(:delete, %{status: "pending"}), do: :error
  defp apply_review(:delete, s), do: Quiz.delete_submission(s)

  defp load(socket) do
    filter = socket.assigns.filter
    status = if filter == "all", do: :all, else: String.to_existing_atom(filter)

    socket
    |> assign(:submissions, Quiz.list_submissions(status))
    |> assign(:pending_count, Quiz.count_submissions(:pending))
    |> then(&assign(&1, :pending_submissions, &1.assigns.pending_count))
  end

  defp status_class("pending"), do: "badge-warning"
  defp status_class("approved"), do: "badge-success"
  defp status_class("rejected"), do: "badge-ghost"
end
