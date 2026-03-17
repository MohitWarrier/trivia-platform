defmodule TriviaPlatform.Rooms.RoomRegistry do
  use GenServer

  @table :room_registry

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def register(room_code, pid) do
    case :ets.insert_new(@table, {room_code, pid}) do
      true -> :ok
      false -> {:error, :already_exists}
    end
  end

  def unregister(room_code) do
    :ets.delete(@table, room_code)
    :ok
  end

  def lookup(room_code) do
    case :ets.lookup(@table, room_code) do
      [{^room_code, pid}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  def list_rooms do
    :ets.tab2list(@table) |> Enum.map(fn {code, _pid} -> code end)
  end

  # Server callbacks

  @impl true
  def init(_) do
    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, table}
  end
end
