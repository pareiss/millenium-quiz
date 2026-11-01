defmodule MillenniumQuizWeb.Admin.BackupLive do
  @moduledoc "Download a backup of the quiz content and restore one from a file."
  use MillenniumQuizWeb, :live_view

  require Logger

  alias MillenniumQuiz.Quiz.Import

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      pending_submissions={@pending_submissions}
    >
      <div class="duel-admin space-y-6">
        <.header>
          Backup
          <:subtitle>
            A backup holds the quiz you wrote: formats, topics, questions, choices and the cards
            linked to each question. It does not hold games, accounts or the card pool; the cards
            are fetched again when you restore. Formats whose name already exists are skipped,
            never overwritten.
          </:subtitle>
        </.header>

        <section class="duel-plate duel-panel rounded-box border border-base-300 bg-base-100 p-5 space-y-3">
          <h2 class="font-semibold">Download backup</h2>
          <p class="text-sm text-base-content/70">
            The file is saved on this device, usually in the Downloads folder. Download a new one
            after every time you change questions, and keep it somewhere safe: a cloud drive, an
            email to yourself or a USB stick. If the site ever loses its data, restore the file
            below.
          </p>
          <a href={~p"/admin/backup.json"} class="btn btn-primary" id="download-backup" download>
            <.icon name="hero-arrow-down-tray" class="size-5" /> Download backup
          </a>
        </section>

        <section class="duel-plate duel-panel rounded-box border border-base-300 bg-base-100 p-5 space-y-3">
          <h2 class="font-semibold">Restore from a backup file</h2>
          <.form for={%{}} id="restore-form" phx-change="validate" phx-submit="ask" class="space-y-3">
            <.live_file_input
              upload={@uploads.backup}
              id="backup-file"
              class="file-input w-full pointer-coarse:min-h-11"
            />
            <p
              :for={entry <- @uploads.backup.entries}
              id={"backup-entry-#{entry.ref}"}
              class="text-sm text-base-content/70"
            >
              {entry.client_name} ({entry.progress}%)
            </p>
            <p
              :for={error <- upload_errors(@uploads.backup)}
              class="text-sm text-error"
              id="backup-upload-error"
            >
              {upload_error(error)}
            </p>
            <p
              :for={entry <- @uploads.backup.entries}
              :if={upload_errors(@uploads.backup, entry) != []}
              class="text-sm text-error"
              id={"backup-entry-error-#{entry.ref}"}
            >
              {Enum.map_join(upload_errors(@uploads.backup, entry), " ", &upload_error/1)}
            </p>
            <.button variant="primary" id="restore-button" disabled={not ready?(@uploads.backup)}>
              <.icon name="hero-arrow-up-tray" class="size-5" /> Restore
            </.button>
          </.form>
        </section>

        <section
          :if={@importing}
          id="restore-running"
          class="duel-plate duel-panel rounded-box border border-base-300 bg-base-100 p-5"
        >
          <span class="loading loading-spinner loading-sm"></span>
          Restoring. Missing cards are fetched one at a time, this can take a while. The restore
          keeps going if you leave this page, and its result is written to the server log; stay
          here to see it.
        </section>

        <section
          :if={@result}
          id="restore-result"
          class="duel-plate duel-panel rounded-box border border-base-300 bg-base-100 p-5 space-y-3"
        >
          <h2 class="font-semibold">Result</h2>
          <ul class="list-disc pl-5 space-y-1 text-sm" id="restore-summary">
            <li :for={{line, i} <- Enum.with_index(@report)} id={"restore-line-#{i}"}>{line}</li>
          </ul>
        </section>

        <.confirm_dialog
          :if={@confirm}
          id="restore-dialog"
          title="Restore this backup?"
          icon="hero-arrow-up-tray"
          on_cancel="cancel"
        >
          <p>
            Formats that are not yet here are created from the file. Formats with the same name are
            skipped and stay as they are.
          </p>
          <:actions>
            <button class="btn btn-ghost" phx-click="cancel" id="restore-dialog-cancel">Cancel</button>
            <button class="btn btn-primary" phx-click="restore" id="restore-dialog-confirm">
              <.icon name="hero-arrow-up-tray" class="size-4" /> Restore
            </button>
          </:actions>
        </.confirm_dialog>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Backup")
     |> assign(:confirm, false)
     |> assign(:importing, false)
     |> assign(:result, nil)
     |> assign(:report, [])
     |> allow_upload(:backup,
       accept: ~w(.json),
       max_entries: 1,
       max_file_size: Import.max_bytes(),
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
       ready?(socket.assigns.uploads.backup) and not socket.assigns.importing
     )}
  end

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, :confirm, false)}

  def handle_event("restore", _params, %{assigns: %{confirm: true, importing: false}} = socket) do
    [json] =
      consume_uploaded_entries(socket, :backup, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    {:noreply,
     socket
     |> assign(confirm: false, importing: true, result: nil)
     |> start_restore(json)}
  end

  def handle_event("restore", _params, socket), do: {:noreply, assign(socket, :confirm, false)}

  # Not linked to this page: a restore with an empty card pool is a long run
  # and must finish when the admin leaves. The result goes to the log, and to
  # the page if it is still there.
  defp start_restore(socket, json) do
    liveview = self()

    {:ok, _pid} =
      Task.Supervisor.start_child(MillenniumQuiz.TaskSupervisor, fn ->
        result =
          try do
            Import.run(json)
          rescue
            e ->
              Logger.error("Quiz restore crashed: " <> Exception.message(e))
              {:error, "The restore stopped unexpectedly. Check the formats and try again."}
          end

        Logger.info(
          "Quiz restore finished:\n" <>
            Enum.join(MillenniumQuiz.Release.import_report(result), "\n")
        )

        send(liveview, {:restore_finished, result})
      end)

    socket
  end

  @impl true
  def handle_info({:restore_finished, result}, socket) do
    {:noreply,
     assign(socket,
       importing: false,
       result: result,
       report: MillenniumQuiz.Release.import_report(result)
     )}
  end

  # Ready when exactly one entry is fully uploaded without errors.
  defp ready?(upload) do
    match?([%{done?: true, valid?: true}], upload.entries) and upload_errors(upload) == []
  end

  defp upload_error(:too_large), do: "The file is larger than 5 MB."
  defp upload_error(:not_accepted), do: "Only .json files can be restored."
  defp upload_error(:too_many_files), do: "Choose one file."
  defp upload_error(_), do: "The file could not be uploaded."
end
