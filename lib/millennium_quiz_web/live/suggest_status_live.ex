defmodule MillenniumQuizWeb.SuggestStatusLive do
  @moduledoc """
  What happened to a suggestion. The private link (`/suggest/:token`) is the
  only way in, there are no accounts. `/suggest/thanks` is the same
  confirmation without a status, for suggestions that were not stored.
  """
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.Quiz
  alias MillenniumQuiz.Quiz.CardLinks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-xl rounded-box border border-base-300 bg-base-100 p-6 sm:p-8 shadow-sm space-y-4">
        <h1 class="text-2xl font-bold tracking-tight">Thank you!</h1>

        <%= if @submission do %>
          <p id="suggestion-status" class="flex items-center gap-2">
            <.icon name={status_icon(@submission.status)} class="size-5 shrink-0" />
            {status_text(@submission.status)}
          </p>
          <div class="rounded-field border border-base-300 p-3 space-y-1" id="suggestion-copy">
            <p class="text-sm text-base-content/60">
              {@submission.topic.format.name} · {@submission.topic.name}
            </p>
            <p class="font-semibold">{CardLinks.plain(@submission.text)}</p>
            <ol class="list-[upper-alpha] pl-6 text-sm">
              <li :for={c <- @submission.choices} class={c.correct && "font-semibold"}>
                {c.text}
              </li>
            </ol>
          </div>
          <p class="text-sm text-base-content/60">
            Keep this page's address to check back later. Anyone with the link can see it.
          </p>
        <% else %>
          <p id="suggestion-status">Your suggestion has been received.</p>
        <% end %>

        <div class="flex gap-2 pt-2">
          <.button navigate={~p"/suggest"} id="suggest-another">Suggest another</.button>
          <.button navigate={~p"/"}>Back to the formats</.button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => "thanks"}, _session, socket), do: {:ok, assign_page(socket, nil)}

  def mount(%{"token" => token}, _session, socket) do
    case Quiz.get_submission_by_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "That suggestion was not found.")
         |> push_navigate(to: ~p"/suggest")}

      submission ->
        {:ok, assign_page(socket, submission)}
    end
  end

  defp assign_page(socket, submission),
    do: socket |> assign(:page_title, "Thank you") |> assign(:submission, submission)

  defp status_icon("pending"), do: "hero-clock"
  defp status_icon("approved"), do: "hero-check-circle"
  defp status_icon("rejected"), do: "hero-x-circle"

  defp status_text("pending"), do: "Waiting for an admin to review it."

  defp status_text("approved"),
    do: "Accepted! It is now a question in the format (an admin may have edited it)."

  defp status_text("rejected"),
    do: "This one was not added. Thanks for trying, you can send another."
end
