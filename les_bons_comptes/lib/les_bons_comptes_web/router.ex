defmodule LesBonsComptesWeb.Router do
  use LesBonsComptesWeb, :router

  import LesBonsComptesWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LesBonsComptesWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LesBonsComptesWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Routes d'authentification et gestion de session (IF-27)
    get "/users/log_in", UserSessionController, :create
    post "/users/log_in", UserSessionController, :create
    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{LesBonsComptesWeb.UserAuth, :mount_current_user}] do
      live "/sign-in", SignInLive
      live "/sign-up", SignUpLive
    end

    live_session :authenticated_user,
      on_mount: [{LesBonsComptesWeb.UserAuth, :ensure_authenticated}] do
      live "/wallets", WalletLive.Index, :index
      live "/wallets/new", WalletLive.New, :new
      live "/wallets/:id", WalletLive.Show, :show
      live "/wallets/:id/edit", WalletLive.Edit, :edit
      live "/wallets/:id/expenses/new", WalletLive.ExpenseNew, :new
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", LesBonsComptesWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:les_bons_comptes, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LesBonsComptesWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
