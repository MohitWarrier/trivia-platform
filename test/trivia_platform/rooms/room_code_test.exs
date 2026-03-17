defmodule TriviaPlatform.Rooms.RoomCodeTest do
  use ExUnit.Case, async: false

  alias TriviaPlatform.Rooms.{RoomCode, RoomRegistry}

  describe "generate/0" do
    test "generates a 6-character alphanumeric code" do
      {:ok, code} = RoomCode.generate()
      assert String.length(code) == 6
      assert code =~ ~r/^[A-Z2-9]+$/
    end

    test "excludes ambiguous characters (O, 0, I, 1)" do
      # Generate many codes and verify none contain ambiguous chars
      codes = for _ <- 1..50, do: elem(RoomCode.generate(), 1)

      for code <- codes do
        refute String.contains?(code, "O")
        refute String.contains?(code, "0")
        refute String.contains?(code, "I")
        refute String.contains?(code, "1")
      end
    end

    test "generates unique codes" do
      codes = for _ <- 1..20, do: elem(RoomCode.generate(), 1)
      assert length(Enum.uniq(codes)) == length(codes)
    end

    test "generated code is not already in the registry" do
      {:ok, code} = RoomCode.generate()
      assert {:error, :not_found} = RoomRegistry.lookup(code)
    end
  end
end
