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
        # 친구 추천 사이드바 / 사용자 목록 캐싱 (60s TTL)
        {Cachex, name: :recommendations_cache},
        # Rate limit (admin login, chat throttle) — Hammer 7.x module-based
        HappyTrizn.RateLimit,
        # MongoDB — url 환경변수 있을 때만 시작 (호스트 직접 test 시 mongo 없을 수 있음)
        if(mongo_url,
          do:
            {Mongo,
             [name: :mongo, url: mongo_url, pool_size: Keyword.get(mongo_cfg, :pool_size, 5)]}
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

end
