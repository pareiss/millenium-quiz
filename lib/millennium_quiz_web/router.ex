defmodule MillenniumQuizWeb.Router do
  use MillenniumQuizWeb, :router

  import MillenniumQuizWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MillenniumQuizWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  ## Players

  scope "/", MillenniumQuizWeb do
    pipe_through :browser

    live_session :public, on_mount: [{MillenniumQuizWeb.UserAuth, :mount_current_scope}] do
      live "/", HomeLive
      live "/categories/:id/play", NewGameLive
      live "/games/:id", GameLive
    end
  end

  ## Admin

  scope "/admin", MillenniumQuizWeb.Admin do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :admin_login,
      on_mount: [{MillenniumQuizWeb.UserAuth, :mount_current_scope}] do
      live "/login", LoginLive
    end

    post "/login", SessionController, :create
  end

  scope "/admin", MillenniumQuizWeb.Admin do
    pipe_through [:browser, :require_authenticated_user]

    live_session :admin,
      on_mount: [{MillenniumQuizWeb.UserAuth, :require_authenticated}] do
      live "/categories", CategoryLive.Index, :index
      live "/categories/new", CategoryLive.Form, :new
      live "/categories/:id", CategoryLive.Show, :show
      live "/categories/:id/edit", CategoryLive.Form, :edit
      live "/topics/:topic_id/questions/new", QuestionLive.Form, :new
      live "/questions/:id/edit", QuestionLive.Form, :edit
      live "/users", UserLive.Index, :index
    end

    put "/password", SessionController, :update_password
    delete "/logout", SessionController, :delete
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:millennium_quiz, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MillenniumQuizWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
