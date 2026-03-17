defmodule TriviaPlatform.Rooms.RateLimiter do
  @moduledoc """
  Simple ETS-based rate limiter for room creation.
  Limits room creation per client to prevent spam.
  """
  use GenServer

  @table :rate_limiter
  @max_rooms_per_minute 5
  @cleanup_interval 60_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Check if a key (e.g., IP or session ID) is allowed to create a room.
  Returns :ok or {:error, :rate_limited}.
  """
  def check(key) do
    now = System.system_time(:second)
    window_start = now - 60

    case :ets.lookup(@table, key) do
      [{^key, timestamps}] ->
        recent = Enum.filter(timestamps, &(&1 > window_start))

        if length(recent) >= @max_rooms_per_minute do
          {:error, :rate_limited}
        else
          :ets.insert(@table, {key, [now | recent]})
          :ok
        end

      [] ->
        :ets.insert(@table, {key, [now]})
        :ok
    end
  end

  @impl true
  def init(_) do
    table = :ets.new(@table, [:set, :public, :named_table])
    schedule_cleanup()
    {:ok, table}
  end

  @impl true
  def handle_info(:cleanup, table) do
    now = System.system_time(:second)
    window_start = now - 60

    :ets.foldl(
      fn {key, timestamps}, _acc ->
        recent = Enum.filter(timestamps, &(&1 > window_start))

        if recent == [] do
          :ets.delete(@table, key)
        else
          :ets.insert(@table, {key, recent})
        end
      end,
      nil,
      table
    )

    schedule_cleanup()
    {:noreply, table}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
