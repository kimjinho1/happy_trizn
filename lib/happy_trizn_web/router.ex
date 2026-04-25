defmodule HappyTriznWeb.Router do
  use HappyTriznWeb, :router

  alias HappyTriznWeb.Plugs.{FetchCurrentUser, EnsureAdmin}

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HappyTriznWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug FetchCurrentUser
  end

  pipeline :admin do
    plug EnsureAdmin
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", HappyTriznWeb do
    pipe_through :browser

    get "/", PageController, :home

    # 게스트 입장 (닉네임만)
    post "/guest", SessionController, :guest

    # 등록자 로그인 / 로그아웃
    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete

    # 회원가입
    get "/register", RegistrationController, :new
    post "/register", RegistrationController, :create

    # 로비 — LiveView (글로벌 채팅, 친구 사이드바, 방 리스트, 게임 카테고리).
    live_session :default,
      on_mount: HappyTriznWeb.Live.Hooks.FetchLiveUser do
      live "/lobby", LobbyLive

      # Sprint 3 에서 GameLive 로 교체. 현재는 placeholder.
      live "/game/:game_type/:room_id", GamePlaceholderLive
      live "/play/:game_type", GamePlaceholderLive
    end

    # Admin 로그인 (browser pipeline, EnsureAdmin 미적용 — 로그인 폼 자체)
    get "/admin/login", AdminSessionController, :new
    post "/admin/login", AdminSessionController, :create
    delete "/admin/logout", AdminSessionController, :delete
  end

  # Admin 페이지 (EnsureAdmin 가드)
  scope "/admin", HappyTriznWeb do
    pipe_through [:browser, :admin]

    get "/", AdminController, :index
    get "/users", AdminController, :users
    post "/users/:id/ban", AdminController, :ban
    post "/users/:id/unban", AdminController, :unban
  end

  # Other scopes may use custom stacks.
  # scope "/api", HappyTriznWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:happy_trizn, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HappyTriznWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
