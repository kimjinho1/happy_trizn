defmodule HappyTrizn.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    mongo_cfg = Application.get_env(:happy_trizn, :mongo, [])
    mongo_url = Keyword.get(mongo_cfg, :url)

    children =
      [
        HappyTriznWeb.Telemetry,
        HappyTrizn.Repo,
        {DNSCluster, query: Application.get_env(:happy_trizn, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: HappyTrizn.PubSub},
        # Sprint 4g — 접속 중 사용자 추적 (친구 list online indicator).
        HappyTriznWeb.Presence,
        # 친구 추천 사이드바 / 사용자 목록 캐싱 (60s TTL)
        {Cachex, name: :recommendations_cache},
        # Rate limit (admin login, chat throttle) — Hammer 7.x module-based
        HappyTrizn.RateLimit,
        # GameSession process registry — 방 1개당 GenServer 1개 lookup.
        {Registry, keys: :unique, name: HappyTrizn.Games.SessionRegistry},
        # GameSession DynamicSupervisor — 방마다 spawn / 죽으면 정리.
        {DynamicSupervisor, name: HappyTrizn.Games.SessionSupervisor, strategy: :one_for_one},
        # Sprint 4l — orphan room sweeper (DB open / GameSession nil → 강제 close).
        # boot 즉시 1회 + 5분 주기. test 환경에선 enabled: false 로 무력화.
        {HappyTrizn.Rooms.Cleanup, rooms_cleanup_opts()},
        # MongoDB — url 환경변수 있을 때만 시작 (호스트 직접 test 시 mongo 없을 수 있음)
        if(mongo_url,
          do:
            {Mongo,
             [name: :mongo, url: mongo_url, pool_size: Keyword.get(mongo_cfg, :pool_size, 5)]}
        ),
        # GameEvents Broadway pipeline — Producer → batcher → Mongo bulk insert.
        # Mongo 미연결이라도 Producer 큐는 정상 — batch handler 가 silent skip.
        # test.exs 에서 game_events: [enabled: false] → 미시작.
        if(game_events_enabled?(),
          do: HappyTrizn.GameEvents.Pipeline
        ),
        # Phoenix endpoint must be last
        HappyTriznWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HappyTrizn.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HappyTriznWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp game_events_enabled? do
    Application.get_env(:happy_trizn, :game_events, [])
    |> Keyword.get(:enabled, true)
  end

  defp rooms_cleanup_opts do
    Application.get_env(:happy_trizn, :rooms_cleanup, [])
  end
end
