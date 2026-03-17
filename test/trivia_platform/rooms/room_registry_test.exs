defmodule TriviaPlatform.Rooms.RoomRegistryTest do
  use ExUnit.Case, async: false

  alias TriviaPlatform.Rooms.RoomRegistry

  describe "register/2" do
    test "registers a room code to a pid" do
      assert :ok = RoomRegistry.register("TEST01", self())
      assert {:ok, pid} = RoomRegistry.lookup("TEST01")
      assert pid == self()

      # Cleanup
      RoomRegistry.unregister("TEST01")
    end

    test "returns error if code already exists" do
      :ok = RoomRegistry.register("TEST02", self())
      assert {:error, :already_exists} = RoomRegistry.register("TEST02", self())

      RoomRegistry.unregister("TEST02")
    end
  end

  describe "unregister/1" do
    test "removes a registered room" do
      :ok = RoomRegistry.register("TEST03", self())
      assert :ok = RoomRegistry.unregister("TEST03")
      assert {:error, :not_found} = RoomRegistry.lookup("TEST03")
    end
  end

  describe "lookup/1" do
    test "returns pid for registered room" do
      :ok = RoomRegistry.register("TEST04", self())
      assert {:ok, pid} = RoomRegistry.lookup("TEST04")
      assert pid == self()

      RoomRegistry.unregister("TEST04")
    end

    test "returns error for unregistered room" do
      assert {:error, :not_found} = RoomRegistry.lookup("NOPE99")
    end
  end

  describe "list_rooms/0" do
    test "lists registered room codes" do
      :ok = RoomRegistry.register("LIST01", self())
      :ok = RoomRegistry.register("LIST02", self())

      rooms = RoomRegistry.list_rooms()
      assert "LIST01" in rooms
      assert "LIST02" in rooms

      RoomRegistry.unregister("LIST01")
      RoomRegistry.unregister("LIST02")
    end
  end
end
