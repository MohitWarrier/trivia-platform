defmodule TriviaPlatform.Questions.AutoRefresh do
  @moduledoc """
  GenServer that periodically imports new questions from the Open Trivia Database.
  Runs on a configurable interval (default: weekly). Only active in production —
  disabled in test/dev by default via application config.
  """

  use GenServer
  require Logger

  alias TriviaPlatform.Questions.Importer

  # Default: 7 days
  @default_interval_ms 7 * 24 * 60 * 60 * 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = opts[:interval_ms] || @default_interval_ms
    enabled = opts[:enabled] != false

    if enabled do
      # Run first import after a short delay (let the app boot first)
      Process.send_after(self(), :import, :timer.seconds(30))
      Logger.info("AutoRefresh started (interval: #{div(interval, 3_600_000)}h)")
    else
      Logger.info("AutoRefresh disabled")
    end

    {:ok, %{interval: interval, enabled: enabled}}
  end

  @impl true
  def handle_info(:import, %{enabled: false} = state) do
    {:noreply, state}
  end

  def handle_info(:import, state) do
    {:ok, count} = Importer.import()
    Logger.info("AutoRefresh: imported #{count} new questions")

    # Schedule next run
    Process.send_after(self(), :import, state.interval)
    {:noreply, state}
  end
end
