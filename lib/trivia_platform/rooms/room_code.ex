defmodule TriviaPlatform.Rooms.RoomCode do
  alias TriviaPlatform.Rooms.RoomRegistry

  @chars ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @code_length 6
  @max_retries 5

  def generate do
    generate(@max_retries)
  end

  defp generate(0), do: {:error, :max_retries_exceeded}

  defp generate(retries) do
    code =
      1..@code_length
      |> Enum.map(fn _ -> Enum.random(@chars) end)
      |> List.to_string()

    case RoomRegistry.lookup(code) do
      {:error, :not_found} -> {:ok, code}
      {:ok, _pid} -> generate(retries - 1)
    end
  end
end
