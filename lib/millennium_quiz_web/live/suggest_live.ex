defmodule MillenniumQuizWeb.SuggestLive do
  @moduledoc """
  Public form where anyone can suggest a question. Nothing entered here reaches
  a game: an admin reviews it first (`Admin.SubmissionLive`).
  """
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.{Cards, Quiz, RateLimit}
  alias MillenniumQuiz.Quiz.{Choice, Question, Submission}
  alias MillenniumQuizWeb.ClientIP

  @remote_suggestions 5

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.link
        navigate={~p"/"}
        class="inline-flex items-center text-sm text-base-content/60 hover:text-base-content pointer-coarse:min-h-11"
      >
        <span aria-hidden="true">&larr;</span> All formats
      </.link>

      <div class="rounded-box border border-base-300 bg-base-100 p-6 sm:p-8 shadow-sm space-y-6">
        <div>
          <p class="text-sm font-medium uppercase tracking-[0.2em] text-primary">Your turn</p>
          <h1 class="text-3xl font-bold tracking-tight">Suggest a question</h1>
          <p class="mt-1 text-base-content/70">
            An admin reads every suggestion and may change it before it goes into a format. Your name, if you give one, is shown with the question.
          </p>
        </div>

        <p :if={@error} class="alert alert-error" id="suggest-error" role="alert">{@error}</p>

        <p :if={@formats == []} class="text-base-content/60" id="no-formats">
          There is no format to suggest a question for yet.
        </p>

        <.form
          :if={@formats != []}
          for={@form}
          id="suggest-form"
          phx-change="validate"
          phx-submit="submit"
          class="space-y-4"
        >
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input
              type="select"
              name="format_id"
              id="suggest-format"
              label="Format"
              value={@format_id}
              options={Enum.map(@formats, &{&1.name, &1.id})}
              prompt="Choose a format"
            />
            <.input
              type="select"
              name="topic_id"
              id="suggest-topic"
              label="Topic"
              value={@topic_id}
              options={Enum.map(@topics, &{&1.name, &1.id})}
              prompt="Choose a topic"
              disabled={@topics == []}
            />
          </div>

          <div class="relative">
            <.input
              field={@form[:text]}
              type="textarea"
              label="Question"
              rows="3"
              maxlength={Question.max_text_length()}
              phx-hook="CardLinkInput"
              data-suggestions="question-text-suggestions"
              role="combobox"
              aria-autocomplete="list"
              aria-controls="question-text-suggestions"
            />
            <ul
              id="question-text-suggestions"
              class="mq-suggestions"
              role="listbox"
              aria-label="Card suggestions"
              phx-update="ignore"
              hidden
            >
            </ul>
          </div>
          <p
            :if={@format_date}
            class="-mt-2 flex items-start gap-2 text-sm text-base-content/70"
            id="card-date-note"
          >
            <.icon name="hero-calendar" class="mt-0.5 size-4 shrink-0" />
            <span>
              Card suggestions only include cards released by {display_date(@format_date)}, the date of this format. A newer card will not show up.
            </span>
          </p>
          <.card_markup_help audience={:player} />

          <fieldset class="space-y-2">
            <legend class="font-medium mb-1">
              Answers
              <span class="text-sm text-base-content/60">
                ({Question.min_choices()}–{Question.max_choices()}, tick the correct one)
              </span>
            </legend>
            <.inputs_for :let={choice} field={@form[:choices]}>
              <div class="grid grid-cols-[2rem_minmax(0,1fr)_auto] items-start gap-x-2 gap-y-1 sm:grid-cols-[2rem_minmax(0,1fr)_auto_auto]">
                <input type="hidden" name="submission[choices_sort][]" value={choice.index} />
                <span class="mt-2 grid place-items-center size-8 shrink-0 rounded-full bg-base-200 text-sm font-semibold">
                  {<<?A + choice.index>>}
                </span>
                <div>
                  <.input
                    field={choice[:text]}
                    placeholder="Answer"
                    maxlength={Choice.max_text_length()}
                  />
                </div>
                <div class="col-start-2 row-start-2 sm:col-start-3 sm:row-start-1 sm:mt-2">
                  <.input
                    field={choice[:correct]}
                    type="checkbox"
                    label="Correct"
                    class="checkbox checkbox-success checkbox-sm mr-1"
                  />
                </div>
                <button
                  type="button"
                  name="submission[choices_drop][]"
                  value={choice.index}
                  phx-click={JS.dispatch("change")}
                  class="btn btn-ghost btn-square col-start-3 row-start-1 mt-0.5 sm:col-start-4"
                  id={"remove-choice-#{choice.index}"}
                  aria-label="Remove answer"
                  title="Remove answer"
                >
                  <.icon name="hero-x-mark" class="size-5" />
                </button>
              </div>
            </.inputs_for>
            <input type="hidden" name="submission[choices_drop][]" />
            <p
              :for={msg <- choice_errors(@form)}
              class="text-sm text-error flex gap-2 items-center"
              id="choice-errors"
            >
              <.icon name="hero-exclamation-circle" class="size-5" /> {msg}
            </p>
            <button
              type="button"
              name="submission[choices_sort][]"
              value="new"
              phx-click={JS.dispatch("change")}
              class="btn btn-ghost btn-sm"
              id="add-choice"
              disabled={length(@form[:choices].value || []) >= Question.max_choices()}
            >
              <.icon name="hero-plus" class="size-4" /> Add answer
            </button>
          </fieldset>

          <.input
            field={@form[:submitter_name]}
            label="Your name (optional)"
            placeholder="Shown with the question"
            maxlength={Submission.max_name_length()}
            autocomplete="nickname"
          />

          <%!-- honeypot: people never see or fill it --%>
          <div class="hidden" aria-hidden="true">
            <label>
              Leave this empty <input type="text" name="website" tabindex="-1" autocomplete="off" />
            </label>
          </div>

          <div class="pt-2">
            <.button variant="primary" phx-disable-with="Sending…" id="send-suggestion">
              Send suggestion
            </.button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    formats = Quiz.list_formats_with_topics()

    {:ok,
     socket
     |> assign(:page_title, "Suggest a question")
     |> assign(:formats, formats)
     |> assign(:format_id, nil)
     |> assign(:topic_id, nil)
     |> assign(:topics, [])
     |> assign(:format_date, nil)
     |> assign(:remote_inflight, nil)
     |> assign(:remote_next, nil)
     |> assign(:error, nil)
     # connect_info is only readable in mount.
     |> assign(:client_ip, ClientIP.from_socket(socket))
     |> assign_form(%Submission{choices: List.duplicate(%Choice{}, 4)})}
  end

  @impl true
  def handle_event("validate", params, socket) do
    socket = select(socket, params)
    changeset = Quiz.change_submission(%Submission{}, params["submission"] || %{})
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate, as: :submission))}
  end

  # Called by the textarea hook while the player types `[Card Name`. Cards of
  # the card pool released by the format's date come first (no network) and are
  # the reply. When there are none, YGOPRODeck is asked for the name in a task,
  # so a slow or busy gate never holds up the form: the reply is `pending` and
  # the names follow as a `card_links:suggestions` event carrying the query they
  # are for. The lookup has the lowest priority at the gate
  # (`YGOPRODeck.Gate`) and a limit per client, so players cannot use up what
  # the admins need; only one runs at a time and of the queries typed meanwhile
  # only the latest is asked. Whatever goes wrong (busy, blocked, limit, error)
  # is just no suggestion. Choosing one only writes the name; an admin attaches
  # the card.
  def handle_event("suggest_cards", %{"query" => query}, socket) when is_binary(query) do
    format = current_format(socket)
    query = String.trim(query)

    cond do
      is_nil(format) ->
        {:reply, %{suggestions: []}, socket}

      pool = pool_suggestions(query, format) ->
        {:reply, %{suggestions: pool}, socket}

      String.length(query) < Cards.min_query_length() ->
        {:reply, %{suggestions: []}, socket}

      true ->
        {:reply, %{suggestions: [], pending: true}, remote_lookup(socket, query)}
    end
  end

  def handle_event("suggest_cards", _params, socket),
    do: {:reply, %{suggestions: []}, socket}

  def handle_event("submit", %{"website" => website}, socket) when website != "" do
    # a bot filled the honeypot: look successful, store nothing
    {:noreply, push_navigate(socket, to: ~p"/suggest/thanks")}
  end

  def handle_event("submit", params, socket) do
    socket = select(socket, params)

    attrs = prune_blank_choices(params["submission"] || %{})

    # Mistakes in the form are not suggestions: only a valid one counts for the limit.
    with {:ok, topic} <- find_topic(socket),
         :ok <- validate(attrs),
         :ok <- rate_limit(socket),
         {:ok, submission} <- Quiz.create_submission(topic, attrs) do
      {:noreply, push_navigate(socket, to: ~p"/suggest/#{submission.token}")}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:error, nil)
         |> assign(:form, to_form(changeset, as: :submission))}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:remote_suggestions, result, socket) do
    socket =
      case result do
        {:ok, {query, suggestions}} ->
          push_event(socket, "card_links:suggestions", %{query: query, suggestions: suggestions})

        # the task died: the hook is told nothing and shows nothing
        {:exit, _reason} ->
          socket
      end

    socket = assign(socket, :remote_inflight, nil)

    case socket.assigns.remote_next do
      nil -> {:noreply, socket}
      query -> {:noreply, socket |> assign(:remote_next, nil) |> remote_lookup(query)}
    end
  end

  # The form starts with four answer fields; a player who needs fewer leaves
  # the rest empty instead of having to remove them.
  defp prune_blank_choices(%{"choices" => choices} = params) when is_map(choices) do
    kept = choices |> Enum.reject(fn {_, c} -> blank?(c) end) |> Map.new()
    sort = for i <- List.wrap(params["choices_sort"]), Map.has_key?(kept, i), do: i

    params |> Map.put("choices", kept) |> Map.put("choices_sort", sort)
  end

  defp prune_blank_choices(params), do: params

  defp blank?(%{"text" => text}) when is_binary(text), do: String.trim(text) == ""
  defp blank?(_), do: true

  defp pool_suggestions(query, format) do
    case Cards.suggest(query, before: format.date) do
      [] -> nil
      cards -> for card <- cards, do: %{id: card.id, name: card.name, source: "pool"}
    end
  end

  defp current_format(socket),
    do: Enum.find(socket.assigns.formats, &(&1.id == socket.assigns.format_id))

  # One lookup at a time; a query that arrives meanwhile waits and a newer one
  # replaces it.
  defp remote_lookup(%{assigns: %{remote_inflight: nil}} = socket, query) do
    format = current_format(socket)
    ip = socket.assigns.client_ip
    limit = fn -> RateLimit.check_rule(:suggest_remote_ip, ip) end

    socket
    |> assign(:remote_inflight, query)
    |> start_async(:remote_suggestions, fn ->
      {query, remote_names(query, format, limit)}
    end)
  end

  defp remote_lookup(socket, query), do: assign(socket, :remote_next, query)

  # `source: "name"`: nothing to import or link, unlike the admin form's list.
  # The client's limit is counted only for a lookup that is not cached.
  defp remote_names(query, format, limit) do
    case Cards.search(query, format, priority: :player, before_request: limit) do
      {:ok, results} ->
        for r <- Enum.take(results, @remote_suggestions),
            do: %{id: r.password, name: r.name, source: "name"}

      {:error, _reason} ->
        []
    end
  end

  defp assign_form(socket, submission),
    do: assign(socket, :form, to_form(Quiz.change_submission(submission), as: :submission))

  # Follows the two pickers; changing the format clears the topic.
  defp select(socket, params) do
    format_id = parse_id(params["format_id"])
    format = Enum.find(socket.assigns.formats, &(&1.id == format_id))
    topics = if format, do: format.topics, else: []
    topic_id = parse_id(params["topic_id"])
    topic_id = if Enum.any?(topics, &(&1.id == topic_id)), do: topic_id

    socket
    |> assign(:format_id, format && format.id)
    |> assign(:format_date, format && format.date)
    |> assign(:topics, topics)
    |> assign(:topic_id, topic_id)
  end

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp parse_id(_), do: nil

  defp find_topic(socket) do
    case Enum.find(socket.assigns.topics, &(&1.id == socket.assigns.topic_id)) do
      nil -> {:error, :no_topic}
      topic -> {:ok, topic}
    end
  end

  defp validate(attrs) do
    changeset = Quiz.change_submission(%Submission{choices: []}, attrs)
    if changeset.valid?, do: :ok, else: {:error, %{changeset | action: :insert}}
  end

  defp rate_limit(socket) do
    case RateLimit.check_all(submit_ip: socket.assigns.client_ip, submit_global: :all) do
      :ok -> :ok
      {:error, retry_after_ms} -> {:error, {:rate_limited, retry_after_ms}}
    end
  end

  defp error_message(:no_topic), do: "Choose a format and a topic first."

  defp error_message(:full),
    do: "Too many suggestions are waiting for review right now. Please try again later."

  defp error_message({:rate_limited, retry_after_ms}),
    do:
      "You have sent a lot of suggestions. Please try again in #{RateLimit.describe_wait(retry_after_ms)}."

  defp choice_errors(form) do
    if form.source.action do
      for {msg, opts} <- Keyword.get_values(form.source.errors, :choices),
          do: translate_error({msg, opts})
    else
      []
    end
  end
end
