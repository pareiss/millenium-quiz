defmodule MillenniumQuizWeb.Admin.LoginLive do
  use MillenniumQuizWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm rounded-box border border-base-300 bg-base-100 p-6 shadow-sm space-y-4">
        <div class="text-center">
          <h1 class="text-2xl font-bold">Admin login</h1>
          <p class="text-sm text-base-content/60">Manage formats, topics and questions.</p>
        </div>
        <%!-- Posted to a controller because only a plain request can set the session cookie. --%>
        <.form for={@form} id="login-form" action={~p"/admin/login"}>
          <.input
            field={@form[:username]}
            label="Username"
            autocomplete="username"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            required
          />
          <button class="btn btn-primary w-full mt-2" id="login-submit">Log in</button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin login")
     |> assign(:form, to_form(%{"username" => "", "password" => ""}, as: :user))}
  end
end
