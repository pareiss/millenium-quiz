defmodule MillenniumQuizWeb.Admin.QuestionLive.Form do
  use MillenniumQuizWeb, :live_view

  import MillenniumQuizWeb.DuelComponents, only: [duel_board: 1, board_button: 1]

  alias MillenniumQuiz.{Cards, Quiz}
  alias MillenniumQuiz.Quiz.{Board, CardLinks, Choice, Question}

  # pasted board JSON; a board is a few KB, this only stops absurd input
  @max_board_bytes 60_000
  @shown_issues 5

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      pending_submissions={@pending_submissions}
    >
      <div class="duel-admin space-y-6">
        <.link
          navigate={@return_to}
          class="duel-back text-sm text-base-content/60 hover:text-base-content"
        >
          <span aria-hidden="true">&larr;</span> {@topic.format.name}
        </.link>
        <.header>
          {@page_title}
          <:subtitle>Topic: {@topic.name}</:subtitle>
        </.header>

        <section
          :if={@submission}
          class="duel-plate duel-sub space-y-2 rounded-box border border-primary/40 bg-primary/5 p-4"
          id="submission-original"
        >
          <h2 class="font-medium">
            <.icon name="hero-light-bulb" class="size-5 text-primary" /> Suggested by a player
          </h2>
          <p class="text-sm text-base-content/60">
            {if @submission.submitter_name,
              do: "From #{@submission.submitter_name}",
              else: "No name given"} · what they wrote is kept as it is; the form below is yours to edit. Saving adds it to this topic and marks the suggestion approved.
          </p>
          <p class="font-semibold whitespace-pre-line" id="original-text">{@submission.text}</p>
          <ol class="list-[upper-alpha] pl-6 text-sm" id="original-choices">
            <li :for={c <- @submission.choices} class={c.correct && "font-semibold"}>{c.text}</li>
          </ol>
        </section>

        <section
          class="duel-plate duel-panel space-y-3 rounded-box border border-base-300 bg-base-100 p-4"
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

          <% first_id = @cards |> List.first() |> then(&(&1 && &1.id)) %>
          <% last_id = @cards |> List.last() |> then(&(&1 && &1.id)) %>
          <ol :if={@cards != []} class="space-y-2" id="selected-cards">
            <li
              :for={card <- @cards}
              id={"selected-card-#{card.id}"}
              class="duel-plate duel-sub rounded-field border border-base-300 p-3 space-y-1"
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
                <div
                  :if={length(@cards) > 1}
                  class="flex shrink-0"
                  role="group"
                  aria-label={"Move #{card.name}"}
                >
                  <button
                    :for={{dir, icon} <- [{"up", "hero-chevron-up"}, {"down", "hero-chevron-down"}]}
                    type="button"
                    class="btn btn-ghost btn-square btn-sm"
                    phx-click="move_card"
                    phx-value-id={card.id}
                    phx-value-dir={dir}
                    id={"move-card-#{card.id}-#{dir}"}
                    aria-label={"Move #{card.name} #{dir}"}
                    disabled={card.id == if(dir == "up", do: first_id, else: last_id)}
                  >
                    <.icon name={icon} class="size-4" />
                  </button>
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
              <div
                class="flex flex-wrap items-center gap-2 text-sm"
                role="group"
                aria-label={"Whose card is #{card.name}?"}
                id={"owner-#{card.id}"}
              >
                <span class="text-base-content/60">Belongs to</span>
                <button
                  :for={{value, label} <- [{"none", "Nobody"}, {"1", "Player 1"}, {"2", "Player 2"}]}
                  type="button"
                  aria-pressed={to_string(owner_value(@owners, card.id) == value)}
                  phx-click="set_owner"
                  phx-value-id={card.id}
                  phx-value-owner={value}
                  id={"owner-#{card.id}-#{value}"}
                  class={[
                    "btn btn-sm",
                    owner_value(@owners, card.id) == value && owner_active(value)
                  ]}
                >
                  {label}
                </button>
              </div>
              <p class="text-sm whitespace-pre-line">{text.text}</p>
            </li>
          </ol>

          <.form
            for={@search_form}
            id="card-search"
            phx-change="search_cards"
            phx-submit="search_cards"
          >
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
            class="max-h-[min(22rem,50dvh)] divide-y divide-base-300 overflow-y-auto overscroll-contain rounded-field border border-base-300"
            id="card-results"
            tabindex="0"
            aria-label="Search results"
          >
            <li :for={result <- @results} class="flex items-center gap-3 px-3 py-2">
              <div class="flex-1 min-w-0">
                <p class="font-medium break-words">{result.name}</p>
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

        <.form
          for={@form}
          id="question-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
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
            and a card name to link a card<span class="hidden [@media(hover:hover)]:inline">;
            <kbd class="kbd kbd-xs">Tab</kbd>
            or <kbd class="kbd kbd-xs">Enter</kbd>
            accepts the suggestion</span>.
            <span class="[@media(hover:hover)]:hidden">Tap a suggestion to insert it.</span>
            <kbd class="kbd kbd-xs">{"{P1}"}</kbd>
            and <kbd class="kbd kbd-xs">{"{P2}"}</kbd>
            mark the two players, in the question or an answer (a blue and a red badge).
          </p>
          <.card_markup_help audience={:admin} />

          <% number = @question.position + 1 %>
          <p class="text-sm text-base-content/60" id="question-damage-note">
            A wrong answer costs {Question.damage(@question.position)} LP, fixed by the question's position ({number}).
          </p>

          <.input
            :if={@show_submitter}
            field={@form[:submitted_by]}
            label="Suggested by (shown on the reveal; empty for none)"
            maxlength={Question.max_submitter_length()}
          />

          <fieldset class="space-y-2">
            <legend class="font-medium mb-1">
              Answers <span class="text-sm text-base-content/60">(2–6, tick the correct one)</span>
            </legend>
            <.answer_markup_hint />
            <.inputs_for :let={choice} field={@form[:choices]}>
              <%!-- letter, answer, remove; "Correct" sits under the answer on a
                 phone and in the row from sm up --%>
              <div class="grid grid-cols-[2rem_minmax(0,1fr)_auto] items-start gap-x-2 gap-y-1 sm:grid-cols-[2rem_minmax(0,1fr)_auto_auto]">
                <input type="hidden" name="question[choices_sort][]" value={choice.index} />
                <span class="mt-2 grid place-items-center size-8 shrink-0 rounded-full bg-base-200 text-sm font-semibold">
                  {<<?A + choice.index>>}
                </span>
                <div class="relative">
                  <.input
                    field={choice[:text]}
                    placeholder="Answer"
                    maxlength="200"
                    autocomplete="off"
                    phx-hook="CardLinkInput"
                    data-mode="plain"
                    aria-describedby="choice-hint"
                    data-suggestions={"choice-suggestions-#{choice.index}"}
                    role="combobox"
                    aria-autocomplete="list"
                    aria-controls={"choice-suggestions-#{choice.index}"}
                  />
                  <ul
                    id={"choice-suggestions-#{choice.index}"}
                    class="mq-suggestions"
                    role="listbox"
                    aria-label="Card suggestions"
                    phx-update="ignore"
                    hidden
                  >
                  </ul>
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
                  name="question[choices_drop][]"
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

          <section
            class="duel-plate duel-sub space-y-3 rounded-field border border-base-300 p-3"
            id="board-section"
          >
            <div class="flex items-start gap-2">
              <div class="min-w-0 flex-1">
                <h2 class="font-medium">
                  Board
                  <span :if={@board_state.board} class="badge badge-ghost badge-sm ml-1">
                    attached
                  </span>
                </h2>
                <p class="text-sm text-base-content/60">
                  Optional: a board players can open while this question is shown. Paste it as stored (with reveal_all); empty means no board.
                </p>
              </div>
              <button
                type="button"
                class="btn btn-ghost btn-sm min-h-11"
                phx-click="toggle_board_section"
                id="toggle-board-section"
                aria-expanded={to_string(@board_open)}
                aria-controls="board-section-body"
              >
                <.icon
                  name={if @board_open, do: "hero-chevron-up", else: "hero-chevron-down"}
                  class="size-4"
                /> {if @board_open, do: "Hide", else: "Show"}
              </button>
            </div>

            <%!-- hidden, not removed, when collapsed: the text must stay in the form --%>
            <div id="board-section-body" class="space-y-3" hidden={!@board_open}>
              <.input
                id="question_board"
                name="question[board]"
                value={@board_text}
                type="textarea"
                label="Board JSON"
                rows="8"
                maxlength={@max_board_bytes}
                spellcheck="false"
                autocomplete="off"
                phx-debounce="500"
                class="w-full textarea font-mono text-xs"
                aria-describedby="board-status"
              />

              <div id="board-status" role="status" class="space-y-1 text-sm">
                <p :if={@board_text == ""} class="text-base-content/60">No board.</p>
                <p
                  :if={@board_text != "" and @board_state.issues == []}
                  class="flex items-center gap-2 text-success"
                  id="board-valid"
                >
                  <.icon name="hero-check-circle" class="size-5 shrink-0" />
                  Valid for {display_date(@topic.format.date)}.
                </p>
                <div :if={@board_state.issues != []} id="board-issues" class="space-y-1 text-error">
                  <p :if={@board_state.board == nil} class="font-medium" id="board-unsaved">
                    This is not a valid board: saving the question leaves it out.
                  </p>
                  <p :if={@board_state.board != nil} class="font-medium" id="board-unfit">
                    Saving keeps this board, but it is not shown in games until these are fixed.
                  </p>
                  <p class="flex items-center gap-2">
                    <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
                    {issue_count(@board_state.issues)}
                  </p>
                  <ul class="list-disc pl-8">
                    <li :for={issue <- Enum.take(@board_state.issues, @shown_issues)}>
                      <span class="font-medium">{issue.path}</span>: {issue.message}
                    </li>
                  </ul>
                  <p :if={length(@board_state.issues) > @shown_issues} class="pl-8">
                    and {length(@board_state.issues) - @shown_issues} more.
                  </p>
                  <p :if={@missing_codes != []} class="pl-8 text-base-content/70" id="board-missing">
                    Not in the card pool: {Enum.join(@missing_codes, ", ")}. Add those cards to a question first.
                  </p>
                </div>
              </div>

              <div class="flex flex-wrap items-center gap-3">
                <.board_button
                  :if={@board_preview}
                  id="board-preview-button"
                  board={@board_preview}
                  on_click="open_board_preview"
                />
                <button
                  type="button"
                  class="btn btn-ghost btn-sm min-h-11"
                  phx-click="remove_board"
                  id="remove-board"
                  disabled={@board_text == ""}
                >
                  <.icon name="hero-trash" class="size-4" /> Remove board
                </button>
              </div>
            </div>
          </section>

          <div class="flex gap-2 pt-2">
            <.button variant="primary" phx-disable-with="Saving…" id="save-question">Save</.button>
            <.button navigate={@return_to}>Cancel</.button>
          </div>
        </.form>

        <.duel_board
          :if={@board_preview && @preview_open}
          id="board-preview"
          board={@board_preview}
          on_close="close_board_preview"
          on_card="board_card"
          selected={@board_selected}
        >
          <:detail :if={@board_card}>
            <div id="board-preview-detail" class="flex flex-col gap-2">
              <img
                :if={@board_card["art"]}
                src={@board_card["art"]}
                alt=""
                class="aspect-square w-full object-cover"
              />
              <h3 class="text-lg font-bold">{@board_card["name"]}</h3>
              <p :if={@board_card["pos"] == "set"} class="text-sm">Face-down</p>
              <p class="text-sm">
                {@board_card["kind"]}<span :if={@board_card["atk"]}> · ATK {@board_card["atk"]}</span><span :if={
                  @board_card["def"]
                }> · DEF {@board_card["def"]}</span>
              </p>
            </div>
          </:detail>
        </.duel_board>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, %{"topic_id" => topic_id} = params) do
    topic = Quiz.get_topic!(topic_id)
    submission = pending_submission(params["submission"], topic)

    question = %Question{
      topic_id: topic.id,
      position: Quiz.next_question_position(topic),
      choices: List.duplicate(%Choice{}, 4)
    }

    question =
      if submission do
        # a copy for the admin to edit; the submission itself stays as written
        %{
          question
          | text: submission.text,
            submitted_by: submission.submitter_name,
            choices: Enum.map(submission.choices, &%Choice{text: &1.text, correct: &1.correct})
        }
      else
        question
      end

    socket
    |> assign(:page_title, if(submission, do: "Review suggestion", else: "New question"))
    |> assign(:submission, submission)
    |> assign_form(topic, question)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    question = Quiz.get_question!(id)
    topic = Quiz.get_topic!(question.topic_id)

    socket
    |> assign(:page_title, "Edit question")
    |> assign(:submission, nil)
    |> assign_form(topic, question)
  end

  # A submission is only reviewed in the topic it was sent for, and only once.
  defp pending_submission(nil, _topic), do: nil

  defp pending_submission(id, topic) do
    case Quiz.get_submission(id) do
      %{status: "pending", topic_id: topic_id} = submission when topic_id == topic.id ->
        submission

      _ ->
        nil
    end
  end

  defp assign_form(socket, topic, question) do
    socket
    |> assign(:topic, topic)
    |> assign(:question, question)
    |> assign(:show_submitter, socket.assigns.submission != nil or question.submitted_by != nil)
    |> assign(:return_to, ~p"/admin/formats/#{topic.format_id}")
    |> assign(:form, to_form(Quiz.change_question(question)))
    |> assign(:cards, cards_of(question))
    |> assign(:owners, owners_of(question))
    |> assign(:search_form, to_form(%{"query" => ""}, as: :card_search))
    |> assign(:results, [])
    |> assign(:search_error, nil)
    |> assign(:importing, nil)
    |> assign(:max_board_bytes, @max_board_bytes)
    |> assign(:shown_issues, @shown_issues)
    |> assign(:board_open, question.board != nil)
    |> assign(:preview_open, false)
    |> assign_board(board_text(question.board))
    |> assign_unlinked_names()
  end

  defp board_text(nil), do: ""
  defp board_text(board), do: Jason.encode!(board, pretty: true)

  # Checks the pasted text against the format's date and keeps what the
  # section shows: the cast board, the issues, the resolved board for the preview.
  defp assign_board(socket, text) do
    text = if is_binary(text), do: String.trim(text), else: ""
    date = socket.assigns.topic.format.date
    state = board_state(text, date)

    socket
    |> assign(:board_text, text)
    |> assign(:board_state, state)
    |> assign(:board_selected, nil)
    |> assign(:board_card, nil)
    |> assign(:missing_codes, Board.missing_passwords(state.issues))
    |> assign(:board_preview, state.board && Board.resolve(state.board, date))
  end

  defp board_state("", _date), do: %{board: nil, issues: []}

  defp board_state(text, _date) when byte_size(text) > @max_board_bytes do
    %{board: nil, issues: [%{kind: :shape, path: "board", message: "is too long", code: nil}]}
  end

  defp board_state(text, date) do
    case Board.cast(text) do
      {:ok, board} ->
        case Board.validate(board, date) do
          :ok -> %{board: board, issues: []}
          {:error, issues} -> %{board: board, issues: issues}
        end

      {:error, issues} ->
        %{board: nil, issues: issues}
    end
  end

  defp issue_count([_]), do: "1 problem with the board:"
  defp issue_count(issues), do: "#{length(issues)} problems with the board:"

  defp owner_value(owners, card_id), do: owners |> Map.get(card_id) |> to_string_or_none()
  defp to_string_or_none(nil), do: "none"
  defp to_string_or_none(n), do: Integer.to_string(n)

  defp owner_active("none"), do: "btn-neutral"
  defp owner_active("1"), do: "border-[#2563eb] bg-[#2563eb] text-white hover:bg-[#1d4ed8]"
  defp owner_active("2"), do: "border-[#dc2626] bg-[#dc2626] text-white hover:bg-[#b91c1c]"

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

  # name starts with the query first, then alphabetical
  defp answer_rank(name, wanted),
    do: {not String.starts_with?(name_key(name), wanted), name_key(name)}

  defp name_key(name), do: name |> String.trim() |> String.downcase()

  defp cards_of(%Question{question_cards: question_cards}) when is_list(question_cards),
    do: Enum.map(question_cards, & &1.card)

  defp cards_of(_question), do: []

  # card id => 1 or 2, for the cards a player owns
  defp owners_of(%Question{question_cards: question_cards}) when is_list(question_cards),
    do: for(%{owner: owner} = qc <- question_cards, owner, into: %{}, do: {qc.card_id, owner})

  defp owners_of(_question), do: %{}

  # the cards in order, each with its owner: what Quiz.create_question/3 takes
  defp card_entries(socket),
    do: Enum.map(socket.assigns.cards, &{&1.id, Map.get(socket.assigns.owners, &1.id)})

  @impl true
  def handle_event("validate", %{"question" => params}, socket) do
    changeset = Quiz.change_question(socket.assigns.question, params)

    # no "board" key: the section is not in the form, the board stays as it is
    # (and typing in the question does not check the board again)
    socket =
      case params do
        %{"board" => text} when is_binary(text) ->
          if String.trim(text) == socket.assigns.board_text,
            do: socket,
            else: assign_board(socket, text)

        _ ->
          socket
      end

    {:noreply,
     socket |> assign(:form, to_form(changeset, action: :validate)) |> assign_unlinked_names()}
  end

  def handle_event("save", %{"question" => params}, socket) do
    socket =
      if Map.has_key?(params, "board"), do: assign_board(socket, params["board"]), else: socket

    # A board is optional: one that does not cast is left out (the stored one stays),
    # one that casts is kept even when it does not fit the format's date.
    %{board: board, issues: issues} = socket.assigns.board_state
    text = socket.assigns.board_text

    cond do
      not Map.has_key?(params, "board") -> save(socket, params, nil)
      text == "" -> save(socket, params, nil)
      board == nil -> save(socket, Map.delete(params, "board"), :not_saved)
      issues == [] -> save(socket, Map.put(params, "board", text), nil)
      true -> save(socket, Map.put(params, "board", text), :problems)
    end
  end

  def handle_event("toggle_board_section", _params, socket),
    do: {:noreply, assign(socket, :board_open, !socket.assigns.board_open)}

  def handle_event("remove_board", _params, socket) do
    params = Map.put(socket.assigns.form.params || %{}, "board", "")
    changeset = Quiz.change_question(socket.assigns.question, params)

    {:noreply,
     socket
     |> assign_board("")
     |> assign(:preview_open, false)
     |> assign(:form, to_form(changeset, action: socket.assigns.form.source.action))}
  end

  def handle_event("open_board_preview", _params, socket),
    do: {:noreply, assign(socket, :preview_open, true)}

  def handle_event("close_board_preview", _params, socket),
    do: {:noreply, assign(socket, preview_open: false, board_selected: nil, board_card: nil)}

  def handle_event("board_card", %{"key" => key}, socket) when is_binary(key) do
    key = if socket.assigns.board_selected == key, do: nil, else: key
    card = key && board_card(socket.assigns.board_preview, key)
    {:noreply, assign(socket, board_selected: card && key, board_card: card)}
  end

  def handle_event("search_cards", %{"card_search" => %{"query" => query}}, socket) do
    socket = assign(socket, :search_form, to_form(%{"query" => query}, as: :card_search))

    case Cards.search(query, socket.assigns.topic.format) do
      {:ok, results} ->
        {:noreply, socket |> assign(:results, results) |> assign(:search_error, nil)}

      {:error, :busy} ->
        {:noreply,
         socket
         |> assign(:results, [])
         |> assign(:search_error, "The card search is busy. Try again in a moment.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:results, [])
         |> assign(:search_error, "The card search is not available right now.")}
    end
  end

  def handle_event("add_card", params, socket), do: start_import(socket, params, :search)

  def handle_event("remove_card", %{"id" => id}, socket) when is_binary(id) do
    with {id, ""} <- Integer.parse(id),
         %{} = card <- Enum.find(socket.assigns.cards, &(&1.id == id)) do
      {:noreply,
       socket
       |> assign(:cards, Enum.reject(socket.assigns.cards, &(&1.id == id)))
       |> assign(:owners, Map.delete(socket.assigns.owners, id))
       |> unlink_in_text(card)
       |> assign_unlinked_names()}
    else
      _ -> {:noreply, socket}
    end
  end

  # An answer field: only the cards already attached to this question, matched
  # in memory. No pool search, no card source request, nothing to import.
  def handle_event("suggest_cards", %{"query" => query, "scope" => "attached"}, socket)
      when is_binary(query) do
    wanted = name_key(query)

    suggestions =
      if String.length(wanted) < Cards.suggest_min_length() do
        []
      else
        for card <- socket.assigns.cards,
            String.contains?(name_key(card.name), wanted),
            do: %{id: card.id, name: card.name, source: "pool"}
      end

    {:reply, %{suggestions: Enum.sort_by(suggestions, &answer_rank(&1.name, wanted))}, socket}
  end

  # One place up or down in the list; the order is the order players see the
  # cards in (saved with the question). The first cannot go up, the last not down.
  def handle_event("move_card", %{"id" => id, "dir" => dir}, socket)
      when is_binary(id) and dir in ["up", "down"] do
    with {id, ""} <- Integer.parse(id),
         i when is_integer(i) <- Enum.find_index(socket.assigns.cards, &(&1.id == id)),
         j = if(dir == "up", do: i - 1, else: i + 1),
         true <- j >= 0 and j < length(socket.assigns.cards) do
      cards = socket.assigns.cards

      moved =
        cards |> List.replace_at(i, Enum.at(cards, j)) |> List.replace_at(j, Enum.at(cards, i))

      {:noreply, assign(socket, :cards, moved)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("move_card", _params, socket), do: {:noreply, socket}

  # Whose card it is: "1", "2" or "none". Only for a card attached to the question.
  def handle_event("set_owner", %{"id" => id, "owner" => owner}, socket)
      when is_binary(id) and owner in ["none", "1", "2"] do
    with {id, ""} <- Integer.parse(id),
         true <- Enum.any?(socket.assigns.cards, &(&1.id == id)) do
      owners =
        case owner do
          "none" -> Map.delete(socket.assigns.owners, id)
          n -> Map.put(socket.assigns.owners, id, String.to_integer(n))
        end

      {:noreply, assign(socket, :owners, owners)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_owner", _params, socket), do: {:noreply, socket}

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

  # "emz:0", "p1:monsters:2": the same keys the board component sends
  defp board_card(board, key) do
    case String.split(key, ":") do
      ["emz", i] -> board["emz"] |> Enum.at(index(i))
      ["p" <> seat, zone, i] -> seat_card(board, seat, zone, index(i))
      _ -> nil
    end
  end

  defp seat_card(board, seat, zone, i) when seat in ["1", "2"] and is_integer(i) do
    player = Enum.at(board["players"], String.to_integer(seat) - 1)

    case zone do
      "field" -> player["field"]
      z when z in ~w(monsters spells hand grave banished extra) -> Enum.at(player[z], i)
      _ -> nil
    end
  end

  defp seat_card(_board, _seat, _zone, _i), do: nil

  defp index(i) do
    case Integer.parse(i) do
      {n, ""} when n >= 0 -> n
      _ -> -1
    end
  end

  defp put_board_flash(socket, nil), do: put_flash(socket, :info, "Question saved.")

  defp put_board_flash(socket, :problems) do
    put_flash(
      socket,
      :info,
      "Saved. The board has problems, so it will not be shown in games until they are fixed."
    )
  end

  defp put_board_flash(socket, :not_saved) do
    put_flash(
      socket,
      :error,
      "The question was saved, but the board was not: it is not a valid board. Edit the question to try again."
    )
  end

  defp save(socket, params, board_note) do
    cards = card_entries(socket)

    result =
      case {socket.assigns.live_action, socket.assigns.submission} do
        {:new, nil} ->
          Quiz.create_question(socket.assigns.topic, params, cards)

        {:new, submission} ->
          Quiz.approve_submission(submission, socket.assigns.topic, params, cards)

        {:edit, _} ->
          Quiz.update_question(socket.assigns.question, params, cards)
      end

    case result do
      {:ok, _question} ->
        {:noreply,
         socket
         |> put_board_flash(board_note)
         |> push_navigate(
           to:
             if(socket.assigns.submission,
               do: ~p"/admin/submissions",
               else: socket.assigns.return_to
             )
         )}

      {:error, :reviewed} ->
        {:noreply,
         socket
         |> put_flash(:error, "That suggestion was already reviewed.")
         |> push_navigate(to: ~p"/admin/submissions")}

      {:error, changeset} ->
        {:noreply, socket |> assign(:form, to_form(changeset)) |> assign_unlinked_names()}
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
