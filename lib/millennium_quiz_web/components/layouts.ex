defmodule MillenniumQuizWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MillenniumQuizWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the app layout: header with player/admin navigation and content.

  ## Examples

      <Layouts.app flash={@flash} current_scope={@current_scope}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :width, :string, default: "md", values: ~w(md lg), doc: "max content width"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%!-- Sticky only where there is room: on a phone (or on its side) the
         header would take a fifth of the screen and cover the page behind it --%>
    <header
      id="site-header"
      class="border-b border-base-300 bg-base-100 [@media(min-width:40rem)_and_(min-height:32rem)]:sticky [@media(min-width:40rem)_and_(min-height:32rem)]:top-0 z-40"
    >
      <nav class="mx-auto max-w-5xl px-4 sm:px-6 h-14 sm:h-16 flex items-center gap-2 sm:gap-3">
        <.link
          navigate={~p"/"}
          class="flex items-center gap-2 group"
          id="brand-link"
          aria-label="Millennium Quiz"
        >
          <span class="grid place-items-center size-9 rounded-xl bg-primary text-primary-content shadow-sm transition-transform group-hover:rotate-6">
            <.icon name="hero-eye" class="size-5" />
          </span>
          <span class="hidden sm:inline font-semibold tracking-tight text-lg">Millennium Quiz</span>
        </.link>

        <div class="flex-1" />

        <%= if @current_scope do %>
          <%!-- from sm up the links sit in the bar; below it they fold into a menu --%>
          <.link navigate={~p"/admin/formats"} class="hidden sm:inline-flex btn btn-ghost btn-sm">
            Formats
          </.link>
          <.link navigate={~p"/admin/users"} class="hidden sm:inline-flex btn btn-ghost btn-sm">
            <.icon name="hero-user-circle" class="size-4" />
            {@current_scope.user.username}
          </.link>
          <.link
            href={~p"/admin/logout"}
            method="delete"
            class="hidden sm:inline-flex btn btn-ghost btn-sm"
            id="logout-link"
          >
            Log out
          </.link>
          <div class="dropdown dropdown-end sm:hidden" id="admin-menu">
            <div
              tabindex="0"
              role="button"
              class="btn btn-ghost btn-sm btn-square"
              aria-label="Admin menu"
              title="Admin menu"
            >
              <.icon name="hero-bars-3" class="size-5" />
            </div>
            <ul class="menu dropdown-content z-50 mt-2 w-52 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg">
              <li><.link navigate={~p"/admin/formats"} id="menu-formats">Formats</.link></li>
              <li>
                <.link navigate={~p"/admin/users"} id="menu-users">
                  <.icon name="hero-user-circle" class="size-4" /> {@current_scope.user.username}
                </.link>
              </li>
              <li>
                <.link href={~p"/admin/logout"} method="delete" id="menu-logout">Log out</.link>
              </li>
            </ul>
          </div>
        <% else %>
          <.link navigate={~p"/admin/login"} class="btn btn-ghost btn-sm opacity-70">Admin</.link>
        <% end %>
        <.theme_toggle />
      </nav>
    </header>

    <main class="px-4 py-6 sm:px-6 sm:py-10">
      <div class={["mx-auto space-y-6", if(@width == "lg", do: "max-w-5xl", else: "max-w-2xl")]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="Use the system theme"
        title="Use the system theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Light theme"
        title="Light theme"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Dark theme"
        title="Dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
