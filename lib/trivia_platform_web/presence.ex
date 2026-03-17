defmodule TriviaPlatformWeb.Presence do
  use Phoenix.Presence,
    otp_app: :trivia_platform,
    pubsub_server: TriviaPlatform.PubSub
end
