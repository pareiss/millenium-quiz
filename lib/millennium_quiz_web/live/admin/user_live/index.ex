defmodule MillenniumQuizWeb.Admin.UserLive.Index do
  use MillenniumQuizWeb, :live_view

  alias MillenniumQuiz.Accounts
  alias MillenniumQuiz.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Admins
        <:subtitle>Everyone listed here can edit all quiz content.</:subtitle>
      </.header>

      <ul class="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100" id="users">
        <li :for={user <- @users} id={"user-#{user.id}"} class="flex items-center gap-3 px-4 py-3">
          <.icon name="hero-user-circle" class="size-6 text-base-content/50" />
          <span class="flex-1 font-medium">{user.username}</span>
          <span :if={user.id == @current_scope.user.id} class="badge badge-ghost badge-sm">you</span>
          <button
            :if={user.id != @current_scope.user.id}
            class="btn btn-ghost btn-xs text-error"
            phx-click="delete"
            phx-value-id={user.id}
            data-confirm={"Remove admin #{user.username}?"}
            id={"delete-user-#{user.id}"}
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
        </li>
      </ul>

      <section class="rounded-box border border-base-300 bg-base-100 p-5 space-y-3">
        <h2 class="font-semibold">Add admin</h2>
        <.form for={@new_form} id="new-user-form" phx-change="validate_new" phx-submit="create">
          <.input field={@new_form[:username]} label="Username" autocomplete="off" />
          <.input
            field={@new_form[:password]}
            type="password"
            label="Password (min. 12 characters)"
            autocomplete="new-password"
          />
          <.button variant="primary" phx-disable-with="Creating…">Create admin</.button>
        </.form>
      </section>

      <section class="rounded-box border border-base-300 bg-base-100 p-5 space-y-3">
        <h2 class="font-semibold">Change my password</h2>
        <.form
          for={@password_form}
          id="password-form"
          action={~p"/admin/password"}
          method="put"
          phx-change="validate_password"
          phx-submit="update_password"
          phx-trigger-action={@trigger_password}
        >
          <.input
            name="current_password"
            id="current-password"
            type="password"
            label="Current password"
            value={@current_password}
            autocomplete="current-password"
            errors={@current_password_errors}
          />
          <.input
            field={@password_form[:password]}
            type="password"
            label="New password"
            autocomplete="new-password"
          />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            autocomplete="new-password"
          />
          <.button variant="primary" phx-disable-with="Saving…">Change password</.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, "Admins")
     |> assign(:users, Accounts.list_users())
     |> assign(:new_form, to_form(Accounts.change_user_registration(%User{}), id: "new_user"))
     |> assign(:password_form, to_form(Accounts.change_user_password(user), id: "password"))
     |> assign(:current_password, nil)
     |> assign(:current_password_errors, [])
     |> assign(:trigger_password, false)}
  end

  @impl true
  def handle_event("validate_new", %{"user" => params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, params, hash_password: false)
    {:noreply, assign(socket, :new_form, to_form(changeset, action: :validate, id: "new_user"))}
  end

  def handle_event("create", %{"user" => params}, socket) do
    case Accounts.register_user(params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Admin #{user.username} created.")
         |> assign(:users, Accounts.list_users())
         |> assign(:new_form, to_form(Accounts.change_user_registration(%User{}), id: "new_user"))}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_form, to_form(changeset, id: "new_user"))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    if user.id != socket.assigns.current_scope.user.id do
      {:ok, _} = Accounts.delete_user(user)
      MillenniumQuizWeb.UserAuth.disconnect_sessions(user)
    end

    {:noreply, assign(socket, :users, Accounts.list_users())}
  end

  def handle_event(
        "validate_password",
        %{"current_password" => current, "user" => params},
        socket
      ) do
    changeset =
      Accounts.change_user_password(socket.assigns.current_scope.user, params,
        hash_password: false
      )

    {:noreply,
     socket
     |> assign(:current_password, current)
     |> assign(:password_form, to_form(changeset, action: :validate, id: "password"))}
  end

  # Validate here, then let the browser submit the form to the controller,
  # which updates the password and renews the session cookie.
  def handle_event("update_password", %{"current_password" => current, "user" => params}, socket) do
    user = socket.assigns.current_scope.user
    changeset = Accounts.change_user_password(user, params, hash_password: false)

    cond do
      not User.valid_password?(user, current) ->
        {:noreply,
         socket
         |> assign(:current_password, current)
         |> assign(:current_password_errors, ["is not valid"])}

      not changeset.valid? ->
        {:noreply,
         assign(socket, :password_form, to_form(changeset, action: :insert, id: "password"))}

      true ->
        {:noreply,
         socket
         |> assign(:current_password, current)
         |> assign(:current_password_errors, [])
         |> assign(:trigger_password, true)}
    end
  end
end
