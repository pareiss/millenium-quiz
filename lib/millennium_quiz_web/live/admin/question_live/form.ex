defmodule MillenniumQuizWeb.Admin.QuestionLive.Form do
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.{Cards, Quiz}
  alias MillenniumQuiz.Quiz.{CardLinks, Choice, Question}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.link navigate={@return_to} class="text-sm text-base-content/60 hover:text-base-content">
        <span aria-hidden="true">&larr;</span> {@topic.format.name}
      </.link>
      <.header>
        {@page_title}
        <:subtitle>Topic: {@topic.name}</:subtitle>
      </.header>

      <section
        class="space-y-3 rounded-box border border-base-300 bg-base-100 p-4"
        id="question-cards"
      >
        <div>
          <h2 class="font-medium">Cards</h2>
          <p class="text-sm text-base-content/60">
            The cards this question is about. Texts are shown as of the format's date, {display_date(
              @topic.format.date
            )}.
          </p>
        </div>

        <ol :if={@cards != []} class="space-y-2" id="selected-cards">
          <li
            :for={card <- @cards}
            id={"selected-card-#{card.id}"}
            class="rounded-field border border-base-300 p-3 space-y-1"
          >
            <% text = Cards.text_on(card, @topic.format.date) %>
            <div class="flex items-start gap-2">
              <div class="flex-1 min-w-0">
                <p class="font-semibold">{card.name}</p>
                <p class="text-xs text-base-content/60">
                  {card.card_type}
                  <span :if={text.set}>
                    · as printed in {text.set}<span :if={text.released_on}> ({text.released_on.year})</span>
                  </span>
                </p>
              </div>
              <button
                type="button"
                class="btn btn-ghost btn-square btn-sm"
                phx-click="remove_card"
                phx-value-id={card.id}
                id={"remove-card-#{card.id}"}
                aria-label={"Remove #{card.name}"}
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
            <p class="text-sm whitespace-pre-line">{text.text}</p>
          </li>
        </ol>

        <.form for={@search_form} id="card-search" phx-change="search_cards" phx-submit="search_cards">
          <.input
            field={@search_form[:query]}
            type="search"
            placeholder={"Search cards released by #{display_date(@topic.format.date)}…"}
            autocomplete="off"
            phx-debounce="300"
          />
        </.form>

        <p :if={@search_error} class="text-sm text-error" id="card-search-error">{@search_error}</p>
        <p class="text-xs text-base-content/50">
          Search by YGOPRODeck; texts and errata from Yugipedia (CC BY-SA 4.0) and YAML Yugi.
        </p>

        <ul
          :if={@results != []}
          class="divide-y divide-base-300 rounded-field border border-base-300"
          id="card-results"
        >
          <li :for={result <- @results} class="flex items-center gap-3 px-3 py-2">
            <div class="flex-1 min-w-0">
              <p class="font-medium truncate">{result.name}</p>
              <p class="text-xs text-base-content/60">
                {result.card_type} · {display_date(result.tcg_release_date)}
                <span :if={result.in_pool} class="badge badge-ghost badge-xs ml-1">in card pool</span>
              </p>
            </div>
            <button
              type="button"
              class="btn btn-sm"
              phx-click="add_card"
              phx-value-password={result.password}
              id={"add-card-#{result.password}"}
              disabled={@importing != nil}
            >
              <span
                :if={importing_password(@importing) == result.password}
                class="loading loading-spinner loading-xs"
              />
              <.icon
                :if={importing_password(@importing) != result.password}
                name="hero-plus"
                class="size-4"
              /> Add
            </button>
          </li>
        </ul>
      </section>

      <.form for={@form} id="question-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <div class="relative">
          <.input
            field={@form[:text]}
            type="textarea"
            label="Question"
            rows="3"
            maxlength="1000"
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
          :if={@unlinked_names != []}
          class="-mt-2 flex items-start gap-2 text-sm text-warning"
          id="unlinked-names"
          role="status"
        >
          <.icon name="hero-exclamation-triangle" class="mt-0.5 size-4 shrink-0" />
          <span>
            No card attached for: {Enum.map_join(@unlinked_names, ", ", &"[#{&1}]")} — they show as plain text to players.
          </span>
        </p>
        <p class="-mt-2 text-xs text-base-content/60" id="card-link-hint">
          Type <kbd class="kbd kbd-xs">[</kbd>
          and a card name to link a card; <kbd class="kbd kbd-xs">Tab</kbd>
          accepts the suggestion.
        </p>

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
    |> assign(:return_to, ~p"/admin/formats/#{topic.format_id}")
    |> assign(:form, to_form(Quiz.change_question(question)))
    |> assign(:cards, cards_of(question))
    |> assign(:search_form, to_form(%{"query" => ""}, as: :card_search))
    |> assign(:results, [])
    |> assign(:search_error, nil)
    |> assign(:importing, nil)
    |> assign_unlinked_names()
  end

  defp importing_password({password, _origin}), do: password
  defp importing_password(nil), do: nil

  # Bracketed names in the current text that no attached card matches; they
  # stay plain text for players (see `CardLinks.parse/2`). Never blocks saving.
  defp assign_unlinked_names(socket) do
    text = Ecto.Changeset.get_field(socket.assigns.form.source, :text)
    attached = MapSet.new(socket.assigns.cards, &name_key(&1.name))

    unlinked = Enum.reject(CardLinks.names(text), &MapSet.member?(attached, name_key(&1)))
    assign(socket, :unlinked_names, unlinked)
  end

  defp name_key(name), do: name |> String.trim() |> String.downcase()

  defp cards_of(%Question{question_cards: question_cards}) when is_list(question_cards),
    do: Enum.map(question_cards, & &1.card)

  defp cards_of(_question), do: []

  @impl true
  def handle_event("validate", %{"question" => params}, socket) do
    changeset = Quiz.change_question(socket.assigns.question, params)

    {:noreply,
     socket |> assign(:form, to_form(changeset, action: :validate)) |> assign_unlinked_names()}
  end

  def handle_event("save", %{"question" => params}, socket) do
    card_ids = Enum.map(socket.assigns.cards, & &1.id)

    result =
      case socket.assigns.live_action do
        :new -> Quiz.create_question(socket.assigns.topic, params, card_ids)
        :edit -> Quiz.update_question(socket.assigns.question, params, card_ids)
      end

    case result do
      {:ok, _question} ->
        {:noreply,
         socket
         |> put_flash(:info, "Question saved.")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, changeset} ->
        {:noreply, socket |> assign(:form, to_form(changeset)) |> assign_unlinked_names()}
    end
  end

  def handle_event("search_cards", %{"card_search" => %{"query" => query}}, socket) do
    socket = assign(socket, :search_form, to_form(%{"query" => query}, as: :card_search))

    case Cards.search(query, socket.assigns.topic.format) do
      {:ok, results} ->
        {:noreply, socket |> assign(:results, results) |> assign(:search_error, nil)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:results, [])
         |> assign(:search_error, "The card search is not available right now.")}
    end
  end

  def handle_event("add_card", params, socket), do: start_import(socket, params, :search)

  def handle_event("remove_card", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(id),
         %{} = card <- Enum.find(socket.assigns.cards, &(&1.id == id)) do
      {:noreply,
       socket
       |> assign(:cards, Enum.reject(socket.assigns.cards, &(&1.id == id)))
       |> unlink_in_text(card)
       |> assign_unlinked_names()}
    else
      _ -> {:noreply, socket}
    end
  end

  # Called by the textarea hook while the admin types `[Card Name`.
  def handle_event("suggest_cards", %{"query" => query}, socket) when is_binary(query) do
    query = String.trim(query)
    format = socket.assigns.topic.format

    suggestions =
      for card <- Cards.suggest(query, before: format.date) do
        %{id: card.id, name: card.name, source: "pool"}
      end

    suggestions =
      if suggestions == [] and String.length(query) >= 3,
        do: remote_suggestions(query, format),
        else: suggestions

    {:reply, %{suggestions: suggestions}, socket}
  end

  def handle_event("suggest_cards", _params, socket),
    do: {:reply, %{suggestions: []}, socket}

  def handle_event("link_card", %{"id" => id}, socket) when is_binary(id) do
    with {id, ""} when id in 1..2_147_483_647//1 <- Integer.parse(id),
         [card] <- Cards.get_cards([id]),
         true <- released_by?(card, socket.assigns.topic.format.date) do
      {:noreply, socket |> add_to_cards(card) |> assign_unlinked_names()}
    else
      _ -> {:noreply, put_flash(socket, :error, "That card is not in the card pool.")}
    end
  end

  def handle_event("link_card", %{"password" => password}, socket) when is_binary(password),
    do: start_import(socket, %{"password" => password}, :text)

  def handle_event("link_card", _params, socket), do: {:noreply, socket}

  # Same rule as `Cards.suggest/2`: no release date counts as released.
  defp released_by?(%{tcg_release_date: nil}, _date), do: true
  defp released_by?(_card, nil), do: true
  defp released_by?(%{tcg_release_date: released}, date), do: Date.compare(released, date) != :gt

  # `origin` is where the import was asked for: the search list or the text.
  defp start_import(socket, %{"password" => password}, origin) when is_binary(password) do
    with {password, ""} <- Integer.parse(password) do
      cond do
        Enum.any?(socket.assigns.cards, &(&1.password == password)) ->
          {:noreply, socket}

        socket.assigns.importing != nil ->
          {:noreply,
           put_flash(socket, :error, "An import is already running, try again in a moment.")}

        true ->
          {:noreply,
           socket
           |> assign(:importing, {password, origin})
           |> start_async(:import_card, fn -> Cards.import(password) end)}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  defp start_import(socket, _params, _origin), do: {:noreply, socket}

  defp remote_suggestions(query, format) do
    case Cards.search(query, format) do
      {:ok, results} ->
        for r <- Enum.take(results, 5),
            do: %{password: r.password, name: r.name, source: "remote"}

      {:error, _reason} ->
        []
    end
  end

  defp add_to_cards(socket, card) do
    cards = socket.assigns.cards

    if Enum.any?(cards, &(&1.id == card.id)),
      do: socket,
      else: assign(socket, :cards, cards ++ [card])
  end

  # Takes the brackets off the card's name in the text as it is right now in
  # the form (not the loaded question) and keeps the other form params.
  defp unlink_in_text(socket, card) do
    form = socket.assigns.form
    text = Ecto.Changeset.get_field(form.source, :text)
    new_text = CardLinks.unlink(text, card.name)

    if text in [nil, new_text] do
      socket
    else
      params = Map.put(form.params || %{}, "text", new_text)
      changeset = Quiz.change_question(socket.assigns.question, params)

      socket
      |> assign(:form, to_form(changeset, action: form.source.action))
      # a focused textarea is not patched by LiveView; tell the hook as well
      |> push_event("card_links:set_text", %{text: new_text})
    end
  end

  @impl true
  def handle_async(:import_card, {:ok, {:ok, card}}, socket) do
    origin = socket.assigns.importing && elem(socket.assigns.importing, 1)

    socket =
      socket
      |> assign(:importing, nil)
      |> add_to_cards(card)

    # only an import from the search list resets the search; one from the text
    # leaves whatever the admin has in the search box
    socket =
      if origin == :search,
        do:
          socket
          |> assign(:results, [])
          |> assign(:search_form, to_form(%{"query" => ""}, as: :card_search)),
        else: socket

    {:noreply, assign_unlinked_names(socket)}
  end

  def handle_async(:import_card, _failed, socket) do
    {:noreply,
     socket
     |> assign(:importing, nil)
     |> put_flash(:error, "The card could not be loaded. Try again in a moment.")
     |> assign_unlinked_names()}
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
