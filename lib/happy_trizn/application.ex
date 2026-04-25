defmodule HappyTrizn.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HappyTriznWeb.Telemetry,
      HappyTrizn.Repo,
      {DNSCluster, query: Application.get_env(:happy_trizn, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: HappyTrizn.PubSub},
      # Start a worker by calling: HappyTrizn.Worker.start_link(arg)
      # {HappyTrizn.Worker, arg},
      # Start to serve requests, typically the last entry
      HappyTriznWeb.Endpoint
    ]

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
