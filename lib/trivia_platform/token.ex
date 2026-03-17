defmodule TriviaPlatform.Token do
  @moduledoc """
  Cryptographic token signing for player identity.

  Player IDs are random strings that identify a player within a room.
  When passed in URLs (for reconnection), they must be signed to prevent
  anyone from forging a player_id and hijacking another player's session.

  Uses Phoenix.Token which is HMAC-based — tied to the endpoint's secret_key_base.
  """

  @salt "player_reconnect"
  @max_age 86_400

  @doc "Sign a player_id into a tamper-proof token."
  def sign(player_id) do
    Phoenix.Token.sign(TriviaPlatformWeb.Endpoint, @salt, player_id)
  end

  @doc "Verify a token and extract the player_id. Expires after 24 hours."
  def verify(token) do
    Phoenix.Token.verify(TriviaPlatformWeb.Endpoint, @salt, token, max_age: @max_age)
  end
end
