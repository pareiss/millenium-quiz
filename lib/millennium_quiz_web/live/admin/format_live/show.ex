defmodule MillenniumQuizWeb.Admin.FormatLive.Show do
  use MillenniumQuizWeb, :live_view

  require Logger

  alias MillenniumQuiz.{Avatars, Cards, Quiz}
  alias MillenniumQuiz.Quiz.{CardLinks, Question}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      pending_submissions={@pending_submissions}
      width="lg"
    >
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
        <div class="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-base-300 px-4 py-3">
          <h2 class="min-w-0 flex-1 basis-40 font-semibold">{topic.name}</h2>
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
            class="flex flex-wrap items-center gap-x-3 gap-y-2 px-4 py-2.5"
          >
            <span class="w-6 text-sm text-base-content/50 tabular-nums">{i + 1}.</span>
            <%!-- the text gets the row's width on a phone (two lines), the
                 points and buttons wrap below it --%>
            <p class="min-w-0 flex-1 basis-40 line-clamp-2 sm:line-clamp-none sm:truncate">
              {CardLinks.plain(q.text)}
            </p>
            <div class="flex w-full items-center justify-between gap-2 sm:w-auto sm:justify-start sm:gap-3">
              <span
                class={["badge badge-sm", if(q.points, do: "badge-secondary", else: "badge-ghost")]}
                title={if q.points, do: "Custom points", else: "Default points from position"}
              >
                {Question.effective_points(q)} {if q.points, do: "custom", else: "pts"}
              </span>
              <div class="flex items-center gap-1">
                <div class="join">
                  <button
                    class="btn btn-ghost btn-xs join-item"
                    phx-click="move"
                    phx-value-id={q.id}
                    phx-value-dir="up"
                    disabled={i == 0}
                    id={"move-up-#{q.id}"}
                    aria-label="Easier"
                    title="Easier"
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
                    title="Harder"
                  >
                    <.icon name="hero-chevron-down" class="size-4" />
                  </button>
                </div>
                <.link
                  navigate={~p"/admin/questions/#{q.id}/edit"}
                  class="btn btn-ghost btn-xs"
                  id={"edit-question-#{q.id}"}
                  aria-label="Edit question"
                  title="Edit question"
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
                  title="Delete question"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </div>
          </li>
        </ol>
      </section>

      <section
        id="avatar-cards"
        class="space-y-3 rounded-box border border-base-300 bg-base-100 p-4 shadow-sm"
      >
        <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
          <h2 class="font-semibold">Profile pictures</h2>
          <span class="text-sm text-base-content/60" id="avatar-count">
            {length(@avatar_cards)} of {Quiz.max_avatar_cards()}
          </span>
        </div>
        <p class="text-sm text-base-content/60">
          Players get a random, different picture from this list and can choose another one.
          With fewer than {Avatars.min_cards()} cards the list is not used (a game of {Avatars.min_cards()} players needs a different picture for each), and neither is it without
          a list: then the built-in set for this format's date (or the default pool of eight) is used.
        </p>

        <ul :if={@avatar_cards != []} class="flex flex-wrap gap-3" id="avatar-card-list">
          <li
            :for={card <- @avatar_cards}
            id={"avatar-card-#{card.id}"}
            class="flex w-24 flex-col items-center gap-1 text-center"
          >
            <.avatar
              slug={Avatars.card_slug(card.id)}
              title={card.name}
              crop={@avatar_crops[Avatars.card_slug(card.id)]}
              class={[
                "size-14",
                @crop_edit && @crop_edit.card.id == card.id && "ring-primary! ring-4!"
              ]}
            />
            <span class="min-h-[2.5em] w-full break-words text-xs leading-tight line-clamp-2">{card.name}</span>
            <div class="flex">
              <button
                type="button"
                class="btn btn-ghost btn-sm min-h-11 min-w-11"
                phx-click="edit_crop"
                phx-value-id={card.id}
                id={"crop-avatar-#{card.id}"}
                aria-label={"Crop #{card.name}"}
                title={"Crop #{card.name}"}
              >
                <.icon name="hero-viewfinder-circle" class="size-5" />
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-sm min-h-11 min-w-11 text-error"
                phx-click="confirm_delete"
                phx-value-what="avatar"
                phx-value-id={card.id}
                id={"remove-avatar-#{card.id}"}
                aria-label={"Remove #{card.name}"}
                title={"Remove #{card.name}"}
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>
          </li>
        </ul>

        <.crop_editor :if={@crop_edit} edit={@crop_edit} form={@crop_form} />
        <p :if={@avatar_cards == []} class="text-sm text-base-content/50" id="avatar-empty">
          No pictures chosen yet.
        </p>

        <.form
          for={@avatar_search_form}
          id="avatar-search"
          phx-change="search_avatar_cards"
          phx-submit="search_avatar_cards"
        >
          <.input
            field={@avatar_search_form[:query]}
            type="search"
            placeholder={"Search cards released by #{display_date(@format.date)}…"}
            autocomplete="off"
            phx-debounce="300"
          />
        </.form>
        <p :if={@avatar_error} class="text-sm text-error" id="avatar-search-error">
          {@avatar_error}
        </p>
        <p class="text-xs text-base-content/50">
          Search by YGOPRODeck; texts and errata from Yugipedia (CC BY-SA 4.0) and YAML Yugi.
        </p>

        <ul
          :if={@avatar_results != []}
          class="max-h-[min(22rem,50dvh)] divide-y divide-base-300 overflow-y-auto overscroll-contain rounded-field border border-base-300"
          id="avatar-results"
          tabindex="0"
          aria-label="Search results"
        >
          <li :for={result <- @avatar_results} class="flex items-center gap-3 px-3 py-2">
            <div class="min-w-0 flex-1">
              <p class="truncate font-medium">{result.name}</p>
              <p class="text-xs text-base-content/60">
                {result.card_type} · {display_date(result.tcg_release_date)}
                <span :if={result.in_pool} class="badge badge-ghost badge-xs ml-1">in card pool</span>
              </p>
            </div>
            <button
              type="button"
              class="btn btn-sm min-h-11"
              phx-click="add_avatar_card"
              phx-value-password={result.password}
              id={"add-avatar-#{result.password}"}
              disabled={@avatar_importing != nil}
            >
              <span
                :if={@avatar_importing == result.password}
                class="loading loading-spinner loading-xs"
              />
              <.icon :if={@avatar_importing != result.password} name="hero-plus" class="size-4" /> Add
            </button>
          </li>
        </ul>
      </section>

      <.confirm_dialog
        :if={@confirm && @confirm.what == :avatar}
        id="remove-avatar-dialog"
        title="Remove this picture?"
        icon="hero-trash"
        on_cancel="cancel_confirm"
      >
        <p>{@confirm.label}</p>
        <p class="mt-2 text-sm text-base-content/60">
          Games that already started keep the pictures their players have.
        </p>
        <:actions>
          <button class="btn btn-ghost" phx-click="cancel_confirm" id="remove-avatar-dialog-cancel">
            Cancel
          </button>
          <button
            class="btn btn-error"
            phx-click="remove_avatar_card"
            phx-value-id={@confirm.id}
            id="remove-avatar-dialog-confirm"
          >
            <.icon name="hero-trash" class="size-4" /> Remove
          </button>
        </:actions>
      </.confirm_dialog>

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

  attr :edit, :map, required: true
  attr :form, :any, required: true

  # The whole artwork with a frame around the part that the round picture
  # shows, three live previews and sliders as the keyboard fallback.
  defp crop_editor(assigns) do
    %{card: card, x: x, y: y, zoom: zoom} = assigns.edit
    crop = %{x: x, y: y, zoom: zoom}
    box = Avatars.crop_box(crop)
    focus_min..focus_max//_ = Avatars.focus_range(zoom)

    assigns =
      assigns
      |> assign(:card, card)
      |> assign(:crop, crop)
      |> assign(:focus_min, focus_min)
      |> assign(:focus_max, focus_max)
      |> assign(:slug, Avatars.card_slug(card.id))
      |> assign(:frame_size, Float.round(10_000 / zoom, 2))
      |> assign(:frame_left, Float.round(-box.left / box.size * 100, 2) + 0.0)
      |> assign(:frame_top, Float.round(-box.top / box.size * 100, 2) + 0.0)

    ~H"""
    <div
      id="crop-editor"
      role="group"
      aria-label={"Crop #{@card.name}"}
      class="space-y-3 rounded-box border border-primary/40 bg-base-200/50 p-3 sm:p-4"
    >
      <div class="flex items-center justify-between gap-2">
        <h3 class="min-w-0 font-semibold break-words">Crop: {@card.name}</h3>
      </div>
      <div class="grid gap-4 sm:grid-cols-[minmax(0,18rem)_minmax(0,1fr)]">
        <div>
          <%!-- Click, tap or drag sets the focus point (the hook sends it);
               touch-none stops the page from scrolling while dragging. --%>
          <div
            id="crop-artwork"
            phx-hook=".CropPicker"
            class="relative aspect-square w-full touch-none overflow-hidden rounded-field bg-base-300 select-none"
          >
            <img
              src={~p"/cards/#{@card.id}/artwork?w=400"}
              alt={"Artwork of #{@card.name}"}
              draggable="false"
              class="pointer-events-none absolute inset-0 size-full"
            />
            <div
              id="crop-frame"
              class="pointer-events-none absolute rounded-full border-2 border-white"
              style={"left:#{@frame_left}%;top:#{@frame_top}%;width:#{@frame_size}%;height:#{@frame_size}%;box-shadow:0 0 0 9999px rgba(0,0,0,.4)"}
            >
            </div>
          </div>
          <p class="mt-1 text-xs text-base-content/60">
            Click or drag on the artwork to choose the centre of the picture.
          </p>
        </div>

        <div class="min-w-0 space-y-3">
          <div class="flex items-end gap-4" id="crop-previews" aria-label="Preview">
            <.avatar slug={@slug} crop={@crop} class="size-11" />
            <.avatar slug={@slug} crop={@crop} class="size-14" />
            <.avatar slug={@slug} crop={@crop} class="size-24" />
          </div>

          <.form for={@form} id="crop-form" phx-change="crop_change" phx-submit="save_crop">
            <.input
              field={@form[:x]}
              id="crop-x"
              type="range"
              min={@focus_min}
              max={@focus_max}
              step="1"
              label={"Horizontal: #{@edit.x}"}
              class="h-11 w-full cursor-pointer accent-primary"
            />
            <.input
              field={@form[:y]}
              id="crop-y"
              type="range"
              min={@focus_min}
              max={@focus_max}
              step="1"
              label={"Vertical: #{@edit.y}"}
              class="h-11 w-full cursor-pointer accent-primary"
            />
            <.input
              field={@form[:zoom]}
              id="crop-zoom"
              type="range"
              min="100"
              max="300"
              step="1"
              label={"Zoom: #{@edit.zoom}%"}
              class="h-11 w-full cursor-pointer accent-primary"
            />
            <div class="flex flex-wrap gap-2 pt-1">
              <button type="submit" class="btn btn-primary min-h-11" id="crop-save">
                <.icon name="hero-check" class="size-4" /> Save
              </button>
              <button type="button" class="btn min-h-11" phx-click="reset_crop" id="crop-reset">
                Reset to default
              </button>
              <button
                type="button"
                class="btn btn-ghost min-h-11"
                phx-click="cancel_crop"
                id="crop-cancel"
              >
                Cancel
              </button>
            </div>
          </.form>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CropPicker">
        // Pointer events cover mouse, pen and touch. Percents are integers 0..100.
        export default {
          mounted() {
            this.el.closest("section")?.scrollIntoView({block: "nearest", behavior: "smooth"})
            this.last = null
            const send = (e) => {
              const r = this.el.getBoundingClientRect()
              const pct = (v, size) => Math.min(100, Math.max(0, Math.round(v / size * 100)))
              const x = pct(e.clientX - r.left, r.width)
              const y = pct(e.clientY - r.top, r.height)
              if (this.last && this.last[0] === x && this.last[1] === y) return
              this.last = [x, y]
              this.pushEvent("crop_focus", {x, y})
            }
            this.el.addEventListener("pointerdown", (e) => {
              if (e.pointerType === "mouse" && e.button !== 0) return
              this.el.setPointerCapture(e.pointerId)
              this.dragging = true
              send(e)
            })
            this.el.addEventListener("pointermove", (e) => { if (this.dragging) send(e) })
            const stop = () => { this.dragging = false }
            this.el.addEventListener("pointerup", stop)
            this.el.addEventListener("pointercancel", stop)
          }
        }
      </script>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:confirm, nil)
     |> assign(:crop_edit, nil)
     |> assign(:crop_form, nil)
     |> assign(:avatar_search_form, to_form(%{"query" => ""}, as: :avatar_search))
     |> assign(:avatar_results, [])
     |> assign(:avatar_error, nil)
     |> assign(:avatar_importing, nil)
     |> assign_format(id)}
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

  def handle_event("confirm_delete", %{"what" => "avatar", "id" => id}, socket) do
    with {:ok, id} <- Ecto.Type.cast(:id, id),
         %{} = card <- Enum.find(socket.assigns.avatar_cards, &(&1.id == id)) do
      {:noreply, assign(socket, :confirm, %{what: :avatar, id: card.id, label: card.name})}
    else
      _ -> {:noreply, socket}
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

  def handle_event("remove_avatar_card", %{"id" => id}, socket) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} ->
        :ok = Quiz.remove_avatar_card(socket.assigns.format.id, id)
        {:noreply, socket |> assign(:confirm, nil) |> assign_format(socket.assigns.format.id)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("search_avatar_cards", %{"avatar_search" => %{"query" => query}}, socket)
      when is_binary(query) do
    socket = assign(socket, :avatar_search_form, to_form(%{"query" => query}, as: :avatar_search))

    case Cards.search(query, socket.assigns.format) do
      {:ok, results} ->
        {:noreply, socket |> assign(:avatar_results, results) |> assign(:avatar_error, nil)}

      {:error, :busy} ->
        {:noreply,
         socket
         |> assign(:avatar_results, [])
         |> assign(:avatar_error, "The card search is busy. Try again in a moment.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:avatar_results, [])
         |> assign(:avatar_error, "The card search is not available right now.")}
    end
  end

  def handle_event("add_avatar_card", %{"password" => password}, socket)
      when is_binary(password) do
    with {password, ""} <- Integer.parse(password) do
      cond do
        Enum.any?(socket.assigns.avatar_cards, &(&1.password == password)) ->
          {:noreply, socket}

        socket.assigns.avatar_importing != nil ->
          {:noreply,
           put_flash(socket, :error, "An import is already running, try again in a moment.")}

        true ->
          {:noreply,
           socket
           |> assign(:avatar_importing, password)
           |> start_async(:import_avatar_card, fn -> Cards.import(password) end)}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  # Only a card of this format's list can be edited, one at a time; the card
  # being edited lives in the socket, so no later event names another one.
  def handle_event("edit_crop", %{"id" => id}, socket) do
    with {:ok, id} <- Ecto.Type.cast(:id, id),
         %{} = card <- Enum.find(socket.assigns.avatar_cards, &(&1.id == id)) do
      crop = socket.assigns.avatar_crops[Avatars.card_slug(card.id)] || Avatars.default_crop()
      {:noreply, assign_crop_edit(socket, Map.put(crop, :card, card))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("crop_focus", %{"x" => x, "y" => y}, %{assigns: %{crop_edit: %{}}} = socket)
      when is_integer(x) and is_integer(y) and x in 0..100 and y in 0..100 do
    {:noreply, assign_crop_edit(socket, %{socket.assigns.crop_edit | x: x, y: y})}
  end

  def handle_event(
        "crop_change",
        %{"crop" => %{"x" => x, "y" => y, "zoom" => zoom}},
        %{assigns: %{crop_edit: %{}}} = socket
      ) do
    with {:ok, x} <- parse_int(x, 0..100),
         {:ok, y} <- parse_int(y, 0..100),
         {:ok, zoom} <- parse_int(zoom, 100..300) do
      {:noreply, assign_crop_edit(socket, %{socket.assigns.crop_edit | x: x, y: y, zoom: zoom})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("save_crop", _params, %{assigns: %{crop_edit: %{card: card} = edit}} = socket) do
    case Quiz.set_avatar_crop(card.id, Map.take(edit, [:x, :y, :zoom])) do
      {:ok, _crop} ->
        {:noreply,
         socket
         |> put_flash(:info, "Crop of #{card.name} saved.")
         |> close_crop_editor()
         |> assign_format(socket.assigns.format.id)}

      {:error, :invalid} ->
        {:noreply,
         put_flash(socket, :error, "That crop is not valid. Move the sliders and try again.")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "That card doesn't exist anymore.")
         |> close_crop_editor()
         |> assign_format(socket.assigns.format.id)}
    end
  end

  def handle_event("reset_crop", _params, %{assigns: %{crop_edit: %{card: card}}} = socket) do
    :ok = Quiz.reset_avatar_crop(card.id)

    {:noreply,
     socket
     |> put_flash(:info, "Crop of #{card.name} reset to the default.")
     |> close_crop_editor()
     |> assign_format(socket.assigns.format.id)}
  end

  def handle_event("cancel_crop", _params, socket), do: {:noreply, close_crop_editor(socket)}

  # malformed events from a hand-made client are ignored
  def handle_event(event, _params, socket)
      when event in [
             "search_avatar_cards",
             "add_avatar_card",
             "remove_avatar_card",
             "edit_crop",
             "crop_focus",
             "crop_change",
             "save_crop",
             "reset_crop"
           ],
      do: {:noreply, socket}

  def handle_event("delete_format", _params, socket) do
    {:ok, _} = Quiz.delete_format(socket.assigns.format)

    {:noreply,
     socket
     |> put_flash(:info, "Format deleted.")
     |> push_navigate(to: ~p"/admin/formats")}
  end

  @impl true
  def handle_async(:import_avatar_card, {:ok, {:ok, card}}, socket) do
    socket = assign(socket, :avatar_importing, nil)

    case Quiz.add_avatar_card(socket.assigns.format.id, card.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:avatar_results, [])
         |> assign(:avatar_error, nil)
         |> assign(:avatar_search_form, to_form(%{"query" => ""}, as: :avatar_search))
         |> assign_format(socket.assigns.format.id)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, avatar_error(reason, card))}
    end
  end

  def handle_async(:import_avatar_card, failed, socket) do
    reason =
      case failed do
        {:ok, {:error, reason}} -> reason
        {:exit, reason} -> {:exit, reason}
        other -> other
      end

    Logger.warning("Importing a profile picture card failed: #{inspect(reason, limit: 5)}")

    {:noreply,
     socket
     |> assign(:avatar_importing, nil)
     |> put_flash(:error, import_error(reason))}
  end

  defp import_error(:blocked),
    do: "The card source (YGOPRODeck) is blocking requests for a few minutes. Try again later."

  defp import_error(:busy), do: "The card source is busy right now. Try again in a moment."
  defp import_error(:not_found), do: "The card source has no such card."

  defp import_error({:exit, _}), do: "The card could not be loaded (it crashed). Try again."

  defp import_error(reason),
    do: "The card could not be loaded (#{short_reason(reason)}). Try again in a moment."

  defp short_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp short_reason({:http, status}) when is_integer(status), do: "HTTP #{status}"

  defp short_reason(%{__exception__: true} = e),
    do: e |> Exception.message() |> String.slice(0, 80)

  defp short_reason(other), do: other |> inspect(limit: 3) |> String.slice(0, 80)

  defp avatar_error(:limit, _card),
    do: "A format can have at most #{Quiz.max_avatar_cards()} profile pictures. Remove one first."

  defp avatar_error(:not_released, card),
    do: "#{card.name} was not released yet at the date of this format."

  defp avatar_error(_other, _card),
    do: "That card or format doesn't exist anymore."

  defp parse_int(value, range) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> if int in range, do: {:ok, int}, else: :error
      _ -> :error
    end
  end

  defp parse_int(_value, _range), do: :error

  defp assign_crop_edit(socket, %{card: _, x: _, y: _, zoom: _} = edit) do
    %{x: x, y: y, zoom: zoom} = edit = Map.merge(edit, Avatars.clamp_focus(edit))

    socket
    |> assign(:crop_edit, edit)
    |> assign(:crop_form, to_form(%{"x" => x, "y" => y, "zoom" => zoom}, as: :crop))
  end

  defp close_crop_editor(socket), do: socket |> assign(:crop_edit, nil) |> assign(:crop_form, nil)

  defp assign_format(socket, id) do
    format = Quiz.get_format!(id)
    cards = Quiz.avatar_cards(format.id)
    slugs = Enum.map(cards, &Avatars.card_slug(&1.id))

    # a card removed meanwhile (here or by another admin) closes its editor
    socket =
      if edit = socket.assigns.crop_edit do
        if Enum.any?(cards, &(&1.id == edit.card.id)), do: socket, else: close_crop_editor(socket)
      else
        socket
      end

    socket
    |> assign(:avatar_cards, cards)
    |> assign(:avatar_crops, Quiz.avatar_crops(slugs, defaults: true))
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
