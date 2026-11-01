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

    live_session :public,
      on_mount: [
        {MillenniumQuizWeb.UserAuth, :mount_current_scope},
        MillenniumQuizWeb.EventLimit
      ] do
      live "/", HomeLive
      live "/formats/:id/play", NewGameLive
      live "/games/:id", GameLive
      live "/suggest", SuggestLive
      live "/suggest/:token", SuggestStatusLive
    end

    get "/categories/*path", LegacyRedirectController, :formats
    get "/admin/categories/*path", LegacyRedirectController, :formats
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
      on_mount: [
        {MillenniumQuizWeb.UserAuth, :require_authenticated},
        MillenniumQuizWeb.AdminPending
      ] do
      live "/formats", FormatLive.Index, :index
      live "/formats/new", FormatLive.Form, :new
      live "/formats/:id", FormatLive.Show, :show
      live "/formats/:id/edit", FormatLive.Form, :edit
      live "/topics/:topic_id/questions/new", QuestionLive.Form, :new
      live "/questions/:id/edit", QuestionLive.Form, :edit
      live "/submissions", SubmissionLive.Index, :index
      live "/users", UserLive.Index, :index
      live "/master-rules", MasterRulesLive, :index
      live "/backup", BackupLive, :index
    end

    get "/backup.json", BackupController, :show
    put "/password", SessionController, :update_password
    delete "/logout", SessionController, :delete
  end

  ## Card pool

  # Artworks are plain images: no session, no CSRF.
  scope "/cards", MillenniumQuizWeb do
    get "/:id/artwork", CardArtworkController, :show
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:millennium_quiz, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MillenniumQuizWeb.Telemetry
      live "/duel", MillenniumQuizWeb.Dev.DuelLive
      live "/board", MillenniumQuizWeb.Dev.BoardLive
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
