defmodule TriviaPlatformWeb.Router do
  use TriviaPlatformWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TriviaPlatformWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", TriviaPlatformWeb do
    pipe_through :browser

    live "/", HomeLive, :index
    live "/host/:code", HostLive, :show
    live "/play/:code", PlayLive, :show
    live "/results/:id", ResultsLive, :show
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:trivia_platform, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TriviaPlatformWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
