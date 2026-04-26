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
      on_mount: [
        HappyTriznWeb.Live.Hooks.FetchLiveUser,
        HappyTriznWeb.Live.Hooks.DmNotifications
      ] do
      live "/lobby", LobbyLive

      # 싱글 게임 (2048 / Minesweeper / Pac-Man stub) — GameLive
      live "/play/:game_type", GameLive

      # 멀티 게임 — GameSession 직접 사용 (Tetris 풀 구현). Channel 분리는 향후.
      live "/game/:game_type/:room_id", GameMultiLive

      # 사용자 게임 옵션 — key bindings + DAS/ARR/grid/ghost/skin/sound.
      live "/settings/games", GameSettingsLive, :index
      live "/settings/games/:game_type", GameSettingsLive, :show

      # 매치 히스토리 + 개인 기록 + 리더보드.
      live "/history", HistoryLive, :index
      live "/history/leaderboard/:game_type", HistoryLive, :leaderboard

      # 마이페이지 — 닉네임 수정 + 프로필 사진 업로드 (등록 사용자 전용).
      live "/me", ProfileLive

      # DM (Direct Messages) — 친구 사이 1:1 채팅.
      live "/dm", DmLive
      live "/dm/:peer_id", DmLive
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
