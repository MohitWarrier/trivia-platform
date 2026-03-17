defmodule TriviaPlatform.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TriviaPlatformWeb.Telemetry,
      TriviaPlatform.Repo,
      {DNSCluster, query: Application.get_env(:trivia_platform, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TriviaPlatform.PubSub},
      TriviaPlatform.Rooms.RoomRegistry,
      TriviaPlatform.Rooms.RateLimiter,
      {DynamicSupervisor, name: TriviaPlatform.Rooms.RoomSupervisor, strategy: :one_for_one},
      TriviaPlatformWeb.Presence,
      TriviaPlatformWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TriviaPlatform.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TriviaPlatformWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
