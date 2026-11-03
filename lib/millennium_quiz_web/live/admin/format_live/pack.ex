defmodule MillenniumQuizWeb.Admin.FormatLive.Pack do
  @moduledoc """
  Imports a pack of questions (JSON from the authoring tool) into one format.
  Questions that fail are listed with the reason; the others are imported.
  """
  use MillenniumQuizWeb, :live_view

  require Logger

  alias MillenniumQuiz.Quiz
  alias MillenniumQuiz.Quiz.{Format, PackImport}

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
          navigate={~p"/admin/formats/#{@format}"}
          class="duel-back text-sm text-base-content/60 hover:text-base-content"
        >
          <span aria-hidden="true">&larr;</span> {@format.name}
        </.link>
        <.header>
          Import a question pack
          <:subtitle>
            A pack is a JSON file of multiple-choice questions in topics, each question optionally
            with a board, written by the authoring tool. Its topics are added to {@format.name}: a
            topic with the same name gets the questions at the hard end, a new topic is created while
            the format has fewer than {Format.max_topics()}. Questions that are already there are
            skipped. A question that fails (for example its board does not fit the format's date)
            is listed in the result and the rest is still imported.
          </:subtitle>
        </.header>

        <section class="duel-plate duel-panel rounded-box border border-base-300 bg-base-100 p-5 space-y-3">
          <.form for={%{}} id="pack-form" phx-change="validate" phx-submit="ask" class="space-y-3">
            <.live_file_input
              upload={@uploads.pack}
              id="pack-file"
              class="file-input w-full pointer-coarse:min-h-11"
            />
            <p
              :for={entry <- @uploads.pack.entries}
              id={"pack-entry-#{entry.ref}"}
              class="text-sm text-base-content/70"
            >
              {entry.client_name} ({entry.progress}%)
            </p>
            <p
              :for={error <- upload_errors(@uploads.pack)}
              class="text-sm text-error"
              id="pack-upload-error"
            >
              {upload_error(error)}
            </p>
            <p
              :for={entry <- @uploads.pack.entries}
              :if={upload_errors(@uploads.pack, entry) != []}
              class="text-sm text-error"
              id={"pack-entry-error-#{entry.ref}"}
            >
              {Enum.map_join(upload_errors(@uploads.pack, entry), " ", &upload_error/1)}
            </p>
            <.button variant="primary" id="pack-button" disabled={not ready?(@uploads.pack)}>
              <.icon name="hero-arrow-up-tray" class="size-5" /> Import
            </.button>
          </.form>
        </section>

        <section
          :if={@importing}
          id="pack-running"
          class="duel-plate duel-panel rounded-box border border-base-300 bg-base-100 p-5"
        >
          <span class="loading loading-spinner loading-sm"></span>
          Importing. Missing cards are fetched one at a time, this can take a while. The import
          keeps going if you leave this page, and its result is written to the server log.
        </section>

        <section
          :if={@error}
          id="pack-error"
          class="duel-plate duel-panel rounded-box border border-error/40 bg-base-100 p-5 text-sm text-error"
        >
          {@error}
        </section>

        <section
          :if={@report}
          id="pack-result"
          class="duel-plate duel-panel rounded-box border border-base-300 bg-base-100 p-5 space-y-3"
        >
          <h2 class="font-semibold">Result</h2>
          <ul class="list-disc pl-5 space-y-1 text-sm break-words" id="pack-summary">
            <li
              :for={{line, i} <- Enum.with_index(PackImport.report_lines(@report))}
              id={"pack-line-#{i}"}
            >
              {line}
            </li>
          </ul>
          <p :if={@report.credits} id="pack-credits" class="text-sm text-base-content/70 break-words">
            Credits of the pack: {@report.credits}
          </p>
          <.link navigate={~p"/admin/formats/#{@format}"} class="btn btn-primary" id="pack-back">
            Back to the format
          </.link>
        </section>

        <.confirm_dialog
          :if={@confirm}
          id="pack-dialog"
          title="Import this pack?"
          icon="hero-arrow-up-tray"
          on_cancel="cancel"
        >
          <p>The questions are added to {@format.name}. Nothing that is already there is changed.</p>
          <:actions>
            <button class="btn btn-ghost" phx-click="cancel" id="pack-dialog-cancel">Cancel</button>
            <button class="btn btn-primary" phx-click="import" id="pack-dialog-confirm">
              <.icon name="hero-arrow-up-tray" class="size-4" /> Import
            </button>
          </:actions>
        </.confirm_dialog>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} -> mount_format(Quiz.get_format!(id), socket)
      :error -> raise Ecto.NoResultsError, queryable: Format
    end
  end

  defp mount_format(format, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Import a pack")
     |> assign(:format, format)
     |> assign(:confirm, false)
     |> assign(:importing, false)
     |> assign(:report, nil)
     |> assign(:error, nil)
     |> allow_upload(:pack,
       accept: ~w(.json),
       max_entries: 1,
       max_file_size: MillenniumQuiz.Quiz.Import.max_bytes(),
       auto_upload: true
     )}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("ask", _params, socket) do
    {:noreply,
     assign(
       socket,
       :confirm,
       ready?(socket.assigns.uploads.pack) and not socket.assigns.importing
     )}
  end

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, :confirm, false)}

  def handle_event("import", _params, %{assigns: %{confirm: true, importing: false}} = socket) do
    [json] =
      consume_uploaded_entries(socket, :pack, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    {:noreply,
     socket
     |> assign(confirm: false, importing: true, report: nil, error: nil)
     |> start_import(json)}
  end

  def handle_event("import", _params, socket), do: {:noreply, assign(socket, :confirm, false)}

  # Not linked to this page: an import with an empty card pool is a long run
  # and must finish when the admin leaves; the result goes to the log.
  defp start_import(socket, json) do
    liveview = self()
    format_id = socket.assigns.format.id

    {:ok, _pid} =
      Task.Supervisor.start_child(MillenniumQuiz.TaskSupervisor, fn ->
        result =
          try do
            PackImport.run(format_id, json)
          rescue
            e ->
              Logger.error("Pack import crashed: " <> Exception.message(e))
              {:error, "The import stopped unexpectedly. Check the format and try again."}
          end

        Logger.info("Pack import finished:\n" <> log_text(result))
        send(liveview, {:pack_finished, result})
      end)

    socket
  end

  defp log_text({:ok, report}), do: Enum.join(PackImport.report_lines(report), "\n")
  defp log_text({:error, message}), do: "Import failed: #{message}"

  @impl true
  def handle_info({:pack_finished, {:ok, report}}, socket),
    do: {:noreply, assign(socket, importing: false, report: report, error: nil)}

  def handle_info({:pack_finished, {:error, message}}, socket),
    do: {:noreply, assign(socket, importing: false, report: nil, error: message)}

  defp ready?(upload) do
    match?([%{done?: true, valid?: true}], upload.entries) and upload_errors(upload) == []
  end

  defp upload_error(:too_large), do: "The file is larger than 5 MB."
  defp upload_error(:not_accepted), do: "Only .json files can be imported."
  defp upload_error(:too_many_files), do: "Choose one file."
  defp upload_error(_), do: "The file could not be uploaded."
end
