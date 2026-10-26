defmodule MillenniumQuizWeb.AdminPending do
  @moduledoc """
  `on_mount` hook of the admin pages: assigns `:pending_submissions`, the
  number of suggested questions waiting for review, which the admin navigation
  shows as a badge. Counted when the page opens (and again by the queue page
  after each action).
  """
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, _session, socket) do
    {:cont, assign(socket, :pending_submissions, MillenniumQuiz.Quiz.count_submissions(:pending))}
  end
end
